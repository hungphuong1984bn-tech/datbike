// Màn "Thu thập bằng chứng Regen" — CHỈ ĐỌC.
//
// Không có nút ghi, không công tắc, không gửi lệnh. Hai việc duy nhất:
//  1) Ghi telemetry xe gửi (dòng pha, điện áp, công suất V×I, tốc độ, ga, ADC)
//     kèm mốc do bạn đánh dấu ("đang đặt Regen mức X", "nhả ga"…) để so sánh các mức.
//  2) Chụp giá trị ĐỌC của các characteristic trước/sau khi bạn đổi Regen bằng app
//     gốc, rồi so sánh để tìm char nào đổi theo. Chỉ gọi lệnh ĐỌC (labRead).
// Kết quả xuất CSV/JSON để đối chiếu với btsnoop và firmware (docs/REGEN_VERIFICATION.md §6).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/brand/app_info.dart';
import '../../core/control/regen_monitor.dart';
import '../../core/regen/regen_analysis.dart';
import '../../core/regen/regen_evidence.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';
import '../firmware_lab/lab_catalog.dart';

/// Char đổi liên tục theo thời gian/telemetry → bỏ khỏi bản chụp (chỉ gây nhiễu khi so sánh).
const _volatilePrefixes = <String>['87efab0d', '2c73e84e', '35a9b4f6'];

String _clean(String uuid) => uuid.replaceAll('-', '').toLowerCase();

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

class RegenEvidenceScreen extends ConsumerStatefulWidget {
  const RegenEvidenceScreen({super.key});

  @override
  ConsumerState<RegenEvidenceScreen> createState() => _RegenEvidenceScreenState();
}

class _RegenEvidenceScreenState extends ConsumerState<RegenEvidenceScreen> {
  final _label = TextEditingController();
  final _note = TextEditingController();

  Map<String, String>? _snapA;
  Map<String, String>? _snapB;
  List<CharChange>? _changes;
  bool _capturing = false;
  String _progress = '';

  static const _noteChips = <String>[
    'Nhả ga hoàn toàn',
    'Phanh tay phải',
    'Phanh tay trái',
    'Xuống dốc',
    'Đứng yên',
  ];

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, String> get _names => {
        for (final t in labCatalog) _clean(t.uuid): t.name,
      };

  /// Chụp giá trị ĐỌC của mọi char đọc được (không ghi gì).
  Future<Map<String, String>?> _capture() async {
    final ble = ref.read(bleProvider);
    if (ble.phase != BlePhase.connected) {
      _toast('Chưa kết nối xe.');
      return null;
    }
    final speed = ble.lastTelemetry?.speed ?? 0;
    if (speed > 1.0) {
      _toast('Xe đang chạy — chỉ chụp snapshot khi xe đứng yên.');
      return null;
    }
    final targets = [
      for (final t in labCatalog)
        if (t.canRead && !_volatilePrefixes.any(_clean(t.uuid).startsWith)) t,
    ];
    final out = <String, String>{};
    setState(() {
      _capturing = true;
      _progress = '0/${targets.length}';
    });
    for (var i = 0; i < targets.length; i++) {
      if (!mounted) return null;
      final t = targets[i];
      final r = await ref.read(bleProvider.notifier).labRead(t.uuid, testId: 'regen_evidence');
      final bytes = r.decrypted ?? r.payload;
      out[_clean(t.uuid)] = !r.ok
          ? 'ERR: ${r.error ?? 'lỗi đọc'}'
          : (bytes.isEmpty ? 'ERR: không có phản hồi' : _hex(bytes));
      if (mounted) setState(() => _progress = '${i + 1}/${targets.length}');
    }
    if (mounted) setState(() => _capturing = false);
    return out;
  }

  Future<void> _takeA() async {
    final m = await _capture();
    if (m == null) return;
    setState(() {
      _snapA = m;
      _snapB = null;
      _changes = null;
    });
  }

  Future<void> _takeB() async {
    final m = await _capture();
    if (m == null || _snapA == null) return;
    setState(() {
      _snapB = m;
      _changes = diffSnapshots(_snapA!, m, names: _names);
    });
  }

  Future<void> _share(String kind) async {
    final st = ref.read(regenEvidenceProvider);
    if (st.samples.isEmpty && _changes == null) {
      _toast('Chưa có dữ liệu để xuất.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final isCsv = kind == 'csv';
      final f = File('${dir.path}/regen_evidence_$stamp.${isCsv ? 'csv' : 'json'}');
      await f.writeAsString(isCsv
          ? evidenceToCsv(st.samples, st.marks)
          : evidenceToJson(
              startedAt: st.startedAt,
              samples: st.samples,
              marks: st.marks,
              changes: _changes ?? const [],
              appVersion: '$kAppName $kAppVersionName',
            ));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path)],
        text: 'Bằng chứng Regen THBIKE (chỉ đọc)',
      ));
    } catch (e) {
      _toast('Lỗi xuất: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(regenEvidenceProvider);
    final ctl = ref.read(regenEvidenceProvider.notifier);
    final connected = ref.watch(bleProvider.select((s) => s.phase == BlePhase.connected));
    final tele = ref.watch(bleProvider.select((s) => s.lastTelemetry));
    final live = connected && ref.read(bleProvider.notifier).telemetryFresh
        ? regenReadingFrom(tele)
        : null;
    final segments = summarizeSegments(st.samples, st.marks);

    String f(double? v, String u, {int d = 1}) => v == null ? '--' : '${v.toStringAsFixed(d)} $u';

    return DsScaffold(
      title: 'Bằng chứng Regen',
      subtitle: 'Chỉ đọc · không gửi lệnh xuống xe',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.huge),
        children: [
          const NoticeBanner(
            color: AppColors.cyan,
            icon: Icons.visibility_rounded,
            text: 'Màn này chỉ ĐỌC và ghi lại. Không có nút ghi, không đổi Regen, '
                'không gửi lệnh nào tới xe. Đổi mức Regen phải làm bằng app gốc của xe.',
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Quy trình ────────────────────────────────────────────────
          const SectionTitle('Quy trình đề xuất'),
          const SizedBox(height: 6),
          GlassCard(
            child: Text(
              '1. Kê chống, xe đứng yên → "Chụp snapshot A".\n'
              '2. Ngắt THBIKE, mở app gốc, đổi Regen sang mức khác, đóng app gốc, '
              'kết nối lại THBIKE.\n'
              '3. "Chụp snapshot B" → xem char nào đổi giá trị.\n'
              '4. Trên đường vắng: bấm "Bắt đầu ghi", đặt tên mức đang dùng, '
              'chạy ~20 km/h rồi nhả ga/phanh, đánh dấu từng lần.\n'
              '5. Lặp lại cho từng mức, rồi xuất CSV/JSON.\n'
              'Song song nên bật btsnoop trên điện thoại khi đổi mức bằng app gốc '
              '(docs/REGEN_VERIFICATION.md §2).',
              style: AppTypography.bodySm(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Số liệu hiện tại ─────────────────────────────────────────
          const SectionTitle('Số liệu xe gửi (trực tiếp)'),
          const SizedBox(height: 6),
          GlassCard(
            child: Row(
              children: [
                _Live('Dòng pha', f(live?.phaseCurrentA, 'A')),
                _Live('Điện áp', f(live?.voltageV, 'V')),
                _Live('V×I', f(live?.powerKw, 'kW', d: 2)),
                _Live('Tốc độ', f(live?.speedKmh, 'km/h', d: 0)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Ghi telemetry ────────────────────────────────────────────
          const SectionTitle('Ghi telemetry theo mốc'),
          const SizedBox(height: 6),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  st.recording
                      ? 'Đang ghi · ${st.samples.length} mẫu · ${st.marks.length} mốc'
                      : (st.samples.isEmpty
                          ? 'Chưa ghi'
                          : 'Đã dừng · ${st.samples.length} mẫu · ${st.marks.length} mốc'),
                  style: AppTypography.labelLg(
                      color: st.recording ? AppColors.tertiary : AppColors.textPrimary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('evidence_toggle'),
                      onPressed: connected || st.recording
                          ? () => st.recording ? ctl.stop() : ctl.start()
                          : null,
                      icon: Icon(st.recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded),
                      label: Text(st.recording ? 'Dừng ghi' : 'Bắt đầu ghi'),
                    ),
                    OutlinedButton.icon(
                      onPressed: st.recording || st.samples.isNotEmpty ? ctl.clear : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Xóa'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Mức Regen đang đặt (theo app gốc / xe)',
                    hintText: 'Ví dụ: Mức 2',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú lần thử',
                    hintText: 'Ví dụ: nhả ga từ 20 km/h, đường bằng',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in _noteChips)
                      ActionChip(
                        label: Text(c),
                        onPressed: () => setState(() {
                          _note.text = _note.text.isEmpty ? c : '${_note.text}, $c';
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: AppSizes.minTap,
                  child: FilledButton.tonalIcon(
                    key: const Key('evidence_mark'),
                    onPressed: st.recording
                        ? () {
                            if (_label.text.trim().isEmpty) {
                              _toast('Nhập tên mức Regen trước khi đánh dấu.');
                              return;
                            }
                            ctl.mark(_label.text, note: _note.text);
                            _note.clear();
                          }
                        : null,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Đánh dấu mốc tại thời điểm này'),
                  ),
                ),
              ],
            ),
          ),

          if (segments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle('Tóm tắt từng mốc'),
            const SizedBox(height: 6),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: AppColors.panelBorder),
                    _SegmentTile(seg: segments[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dấu đã kiểm chứng: dòng pha DƯƠNG = nạp ngược, ÂM = kéo ga. '
              'Cực đại dương = đỉnh nạp ngược; cực tiểu âm = đỉnh kéo ga.',
              style: AppTypography.bodySm(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle('Phân tích mức Regen'),
            const SizedBox(height: 6),
            _AnalysisCard(
              report: RegenAnalysis.analyze(
                [
                  for (final x in st.samples)
                    RegenPoint(
                      ms: x.ms,
                      speedKmh: x.speedKmh,
                      phaseA: x.phaseA,
                      voltageV: x.voltageV,
                      powerKw: x.powerKw,
                      stateIndex: x.stateIndex,
                    ),
                ],
                [for (final m in st.marks) RegenMark(m.ms, m.label)],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          // ── Snapshot characteristic ──────────────────────────────────
          const SectionTitle('So sánh giá trị đọc của characteristic'),
          const SizedBox(height: 6),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chỉ gọi lệnh ĐỌC trên các char đọc được trong Phòng thí nghiệm '
                  '(bỏ qua ${_volatilePrefixes.length} char biến động liên tục). Chỉ chụp khi xe đứng yên.',
                  style: AppTypography.bodySm(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      key: const Key('evidence_snap_a'),
                      onPressed: connected && !_capturing ? _takeA : null,
                      child: Text(_snapA == null ? 'Chụp snapshot A (trước)' : 'Chụp lại A'),
                    ),
                    FilledButton.tonal(
                      key: const Key('evidence_snap_b'),
                      onPressed: connected && !_capturing && _snapA != null ? _takeB : null,
                      child: const Text('Chụp snapshot B (sau) & so sánh'),
                    ),
                  ],
                ),
                if (_capturing) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  Text('Đang đọc… $_progress',
                      style: AppTypography.bodySm(color: AppColors.textSecondary)),
                ],
                if (_snapA != null && !_capturing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('A: ${_snapA!.length} char'
                        '${_snapB == null ? '' : ' · B: ${_snapB!.length} char'}',
                        style: AppTypography.labelMd(color: AppColors.textSecondary)),
                  ),
                if (_changes != null) ...[
                  const Divider(height: 24),
                  if (_changes!.isEmpty)
                    Text(
                      'Không char đọc được nào đổi giữa A và B. Có thể Regen không nằm trong '
                      'các char này (ví dụ cấu hình VESC qua CAN), hoặc bạn chưa đổi mức giữa hai lần chụp.',
                      key: const Key('evidence_no_change'),
                      style: AppTypography.bodySm(color: AppColors.amberText),
                    )
                  else ...[
                    Text('${_changes!.length} char đổi giá trị:',
                        style: AppTypography.labelLg(color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    for (final c in _changes!) _ChangeTile(change: c),
                    const SizedBox(height: 4),
                    Text(
                      'Đây chỉ là ứng viên. Phải đối chiếu btsnoop và firmware trước khi kết luận.',
                      style: AppTypography.bodySm(color: AppColors.textMuted),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Xuất ─────────────────────────────────────────────────────
          const SectionTitle('Xuất dữ liệu'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('evidence_share_csv'),
                onPressed: () => _share('csv'),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Chia sẻ CSV'),
              ),
              OutlinedButton.icon(
                key: const Key('evidence_share_json'),
                onPressed: () => _share('json'),
                icon: const Icon(Icons.data_object_rounded),
                label: const Text('Chia sẻ JSON'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Live extends StatelessWidget {
  final String label;
  final String value;
  const _Live(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: AppTypography.evWide(fontSize: 16, letterSpacing: -0.2)),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.labelSm(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}


/// Kết quả phân tích: dấu dòng pha, từng mức, thứ tự yếu → mạnh.
class _AnalysisCard extends StatelessWidget {
  final RegenReport report;
  const _AnalysisCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final sign = report.sign;
    return GlassCard(
      key: const Key('regen_analysis_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sign.summary,
            key: const Key('regen_analysis_sign'),
            style: AppTypography.bodyMd(
              color: sign.conclusive ? AppColors.greenText : AppColors.amberText,
            ),
          ),
          const SizedBox(height: 10),
          if (report.levels.isEmpty)
            Text(
              'Chưa có mốc mức Regen. Đánh dấu mốc (ví dụ "1".."5" theo app gốc) '
              'trước mỗi lần thử để so sánh các mức.',
              style: AppTypography.bodySm(color: AppColors.textMuted),
            )
          else ...[
            for (final l in report.levels) _LevelRow(stats: l),
            const SizedBox(height: 8),
            if (report.rankWeakToStrong.isNotEmpty)
              Text(
                'Xếp từ YẾU → MẠNH (theo dòng nạp trung bình): '
                '${report.rankWeakToStrong.join(' < ')}',
                key: const Key('regen_analysis_rank'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            'Tổng thu hồi trong phiên: ${report.totalRecoveredWh.toStringAsFixed(1)} Wh '
            '(${report.events.length} đợt nạp).',
            style: AppTypography.bodySm(color: AppColors.textSecondary),
          ),
          for (final n in report.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $n',
                  style: AppTypography.bodySm(color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final RegenLevelStats stats;
  const _LevelRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final decel = stats.meanDecelMs2 == null
        ? '—'
        : '${stats.meanDecelMs2!.toStringAsFixed(2)} m/s²';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text('Mức ${stats.label}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Text(
              'TB ${stats.meanRegenA.toStringAsFixed(1)} A · đỉnh '
              '${stats.peakA.toStringAsFixed(1)} A · '
              '${stats.meanRegenKw.toStringAsFixed(2)} kW · '
              '${stats.energyWh.toStringAsFixed(1)} Wh · giảm tốc $decel · '
              '${stats.events} đợt'
              '${stats.lowData ? '  ⚠ ít dữ liệu' : ''}',
              style: AppTypography.bodySm(
                color: stats.lowData
                    ? AppColors.amberText
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  final SegmentSummary seg;
  const _SegmentTile({required this.seg});

  String _f(double? v, int d) => v == null ? '--' : v.toStringAsFixed(d);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(seg.mark.label,
              style: AppTypography.labelLg(color: AppColors.textPrimary)),
          if (seg.mark.note.isNotEmpty)
            Text(seg.mark.note, style: AppTypography.bodySm(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            seg.sampleCount == 0
                ? 'Chưa có mẫu trong đoạn này.'
                : '${seg.sampleCount} mẫu · ${_f(seg.durationS, 1)} s · '
                    'tốc độ ${_f(seg.speedStartKmh, 0)}→${_f(seg.speedEndKmh, 0)} km/h\n'
                    'dòng pha ${_f(seg.phaseMinA, 1)} … ${_f(seg.phaseMaxA, 1)} A · '
                    'V×I ${_f(seg.powerMinKw, 2)} … ${_f(seg.powerMaxKw, 2)} kW',
            style: AppTypography.bodySm(color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _ChangeTile extends StatelessWidget {
  final CharChange change;
  const _ChangeTile({required this.change});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${change.name}  (${change.uuid.length >= 8 ? change.uuid.substring(0, 8) : change.uuid})',
              style: AppTypography.labelMd(color: AppColors.textPrimary)),
          Text('trước: ${change.before ?? '—'}',
              style: AppTypography.bodySm(color: AppColors.textSecondary)),
          Text('sau:   ${change.after ?? '—'}',
              style: AppTypography.bodySm(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
