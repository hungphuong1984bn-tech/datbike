// Battery Cell Protection Center: tổng quan an toàn, danh sách cảnh báo chi tiết,
// các hạng mục đang giám sát, cấu hình ngưỡng và nhật ký cảnh báo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/battery/battery_config.dart';
import '../../../core/battery/battery_hub.dart';
import '../../../core/battery/cell_model.dart';
import '../../../core/battery/cell_protection_engine.dart';
import '../bms_theme.dart';

class ProtectionView extends ConsumerWidget {
  const ProtectionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(batteryHubProvider);
    final report = hub.report;
    final live = hub.freshness == BmsFreshness.live;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DataStateBanner(freshness: hub.freshness, receivedAt: hub.latest?.receivedAt),
        _OverallCard(hub: hub),
        const SizedBox(height: 16),
        SectionHeader(
          'Cảnh báo đang hoạt động',
          trailing: Text('${report.alerts.length}', style: Bms.number(13, Bms.textDim)),
        ),
        if (report.alerts.isEmpty)
          GlassCard(
            child: Row(
              children: [
                Icon(live ? Icons.verified_user_rounded : Icons.help_outline_rounded,
                    color: live ? Bms.ok : Bms.invalid, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    live
                        ? 'NORMAL — không phát hiện bất thường theo các hạng mục đang giám sát.'
                        : 'Không đánh giá được: dữ liệu BMS không còn trực tiếp.',
                    style: Bms.body(13),
                  ),
                ),
              ],
            ),
          )
        else
          for (final a in report.alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AlertCard(alert: a),
            ),
        const SizedBox(height: 10),
        const SectionHeader('Hạng mục giám sát'),
        _MonitoredItems(hub: hub),
        const SizedBox(height: 16),
        SectionHeader(
          'Ngưỡng cảnh báo',
          trailing: TextButton.icon(
            onPressed: () => _openConfig(context, ref, hub.config),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Cấu hình'),
            style: TextButton.styleFrom(foregroundColor: Bms.accent),
          ),
        ),
        _ThresholdSummary(cfg: hub.config),
        const SizedBox(height: 16),
        SectionHeader(
          'Nhật ký cảnh báo',
          trailing: Text('${hub.alertLog.length}', style: Bms.number(13, Bms.textDim)),
        ),
        _AlertLog(entries: hub.alertLog),
      ],
    );
  }

  void _openConfig(BuildContext context, WidgetRef ref, BatteryConfig cfg) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Bms.bgMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfigSheet(initial: cfg),
    );
  }
}

class _OverallCard extends StatelessWidget {
  final BatteryHubState hub;
  const _OverallCard({required this.hub});

  @override
  Widget build(BuildContext context) {
    final live = hub.freshness == BmsFreshness.live;
    final sev = hub.report.overall;
    final color = live ? Bms.severityColor(sev) : Bms.invalid;
    final label = live ? sev.label : 'KHÔNG XÁC ĐỊNH';
    final warn = hub.report.count(AlertSeverity.warning);
    final crit = hub.report.count(AlertSeverity.critical);

    return GlassCard(
      blur: true,
      glow: live ? color : null,
      borderColor: color.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Icon(
              !live
                  ? Icons.shield_outlined
                  : (sev == AlertSeverity.normal
                      ? Icons.verified_user_rounded
                      : (sev == AlertSeverity.warning
                          ? Icons.warning_amber_rounded
                          : Icons.gpp_bad_rounded)),
              color: color,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BẢO VỆ CELL PIN',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Bms.textFaint,
                    )),
                const SizedBox(height: 2),
                Text(label, style: Bms.number(26, color)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  FreshnessPill(hub.freshness),
                  if (live) StatusPill(text: '$warn cảnh báo', color: Bms.warning),
                  if (live) StatusPill(text: '$crit nghiêm trọng', color: Bms.critical),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatefulWidget {
  final ProtectionAlert alert;
  const _AlertCard({required this.alert});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final c = Bms.severityColor(a.severity);
    return GlassCard(
      glow: a.severity == AlertSeverity.critical ? c : null,
      borderColor: c.withValues(alpha: 0.55),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(text: a.severity.label, color: c),
              const SizedBox(width: 8),
              Expanded(child: Text(a.title, style: Bms.title(13.5))),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Bms.textDim),
            ],
          ),
          const SizedBox(height: 8),
          Text(a.measured, style: Bms.number(12.5, Bms.text, FontWeight.w500)),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Cell liên quan', a.cellLabels),
                  _kv('Phát sinh lúc', '${formatClock(a.since)} (${AgeText.format(a.since, DateTime.now())})'),
                  _kv('Nguyên nhân có thể', a.cause),
                  _kv('Khuyến nghị', a.recommendation, color: c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: Bms.body(10.5, Bms.textFaint)),
            const SizedBox(height: 1),
            Text(v, style: Bms.body(12.5, color ?? Bms.text)),
          ],
        ),
      );
}

class _MonitoredItems extends StatelessWidget {
  final BatteryHubState hub;
  const _MonitoredItems({required this.hub});

  @override
  Widget build(BuildContext context) {
    final cfg = hub.config;
    final live = hub.freshness == BmsFreshness.live;
    final hasOv = cfg.cellOverVoltWarnV != null || cfg.cellOverVoltCritV != null;
    final hasUv = cfg.cellUnderVoltWarnV != null || cfg.cellUnderVoltCritV != null;

    Widget row(String name, String state, Color color, IconData icon) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: Bms.body(13, Bms.text))),
              Text(state, style: Bms.body(11.5, color)),
            ],
          ),
        );

    final on = live ? Bms.ok : Bms.invalid;
    final onIcon = live ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded;
    final onText = live ? 'Đang giám sát' : 'Tạm dừng (không trực tiếp)';

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          row('Quá áp cell', hasOv ? onText : 'CHƯA CẤU HÌNH ngưỡng',
              hasOv ? on : Bms.warning, hasOv ? onIcon : Icons.rule_rounded),
          row('Thấp áp cell', hasUv ? onText : 'CHƯA CẤU HÌNH ngưỡng',
              hasUv ? on : Bms.warning, hasUv ? onIcon : Icons.rule_rounded),
          row('Chênh lệch điện áp giữa các cell (ΔV)', onText, on, onIcon),
          row('Cell lệch bất thường so với trung bình', onText, on, onIcon),
          row('Dấu hiệu suy giảm (cần đủ lịch sử)', onText, on, onIcon),
          row('Nhiệt độ BMS / pack', onText, on, onIcon),
          row('Cảm biến NTC bất thường', onText, on, onIcon),
          row('Mất dữ liệu cell / dữ liệu lỗi', 'Luôn giám sát', Bms.ok, Icons.check_circle_rounded),
          row('Đồng bộ dữ liệu BMS (tổng cell ↔ pack)', onText, on, onIcon),
          row('Cờ bảo vệ / mã lỗi do BMS báo', onText, on, onIcon),
        ],
      ),
    );
  }
}

class _ThresholdSummary extends StatelessWidget {
  final BatteryConfig cfg;
  const _ThresholdSummary({required this.cfg});

  String _v(double? v) => v == null ? 'tắt' : '${v.toStringAsFixed(3)} V';

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(k, style: Bms.body(12.5))),
              Text(v, style: Bms.number(13, Bms.text, FontWeight.w600)),
            ],
          ),
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Quá áp cell  WARNING / CRITICAL',
              '${_v(cfg.cellOverVoltWarnV)} / ${_v(cfg.cellOverVoltCritV)}'),
          row('Thấp áp cell  WARNING / CRITICAL',
              '${_v(cfg.cellUnderVoltWarnV)} / ${_v(cfg.cellUnderVoltCritV)}'),
          row('ΔV  WARNING / CRITICAL',
              '${cfg.deltaWarnMv.toStringAsFixed(0)} / ${cfg.deltaCritMv.toStringAsFixed(0)} mV'),
          row('Lệch so với TB  WARNING / CRITICAL',
              '${cfg.cellDeviationWarnMv.toStringAsFixed(0)} / ${cfg.cellDeviationCritMv.toStringAsFixed(0)} mV'),
          row('Nhiệt độ  WARNING / CRITICAL',
              '${cfg.tempWarnC.toStringAsFixed(0)} / ${cfg.tempCritC.toStringAsFixed(0)} °C'),
          const SizedBox(height: 8),
          Text(
            cfg.hasAbsoluteVoltageLimits
                ? 'Ngưỡng điện áp cell do bạn nhập. Hãy đối chiếu thông số cell của nhà sản xuất.'
                : 'Ngưỡng quá áp/thấp áp cell đang TẮT: ứng dụng không biết loại cell hoá học nên không tự đặt. '
                    'Nhập theo thông số BMS/nhà sản xuất để bật. Các ngưỡng còn lại là mặc định của ứng dụng, không phải thông số nhà sản xuất.',
            style: Bms.body(11.5, Bms.textFaint),
          ),
        ],
      ),
    );
  }
}

class _AlertLog extends StatelessWidget {
  final List<AlertLogEntry> entries;
  const _AlertLog({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return GlassCard(
        child: Text('Chưa có cảnh báo nào được ghi nhận trong phiên này.', style: Bms.body(12.5)),
      );
    }
    final list = entries.reversed.take(30).toList();
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(color: Bms.border, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Bms.severityColor(list[i].severity),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(list[i].title, style: Bms.body(12.5, Bms.text)),
                        const SizedBox(height: 2),
                        Text(
                          '${formatClock(list[i].startedAt)} → '
                          '${list[i].clearedAt == null ? 'đang hoạt động' : formatClock(list[i].clearedAt!)}'
                          '${list[i].cellIndices.isEmpty ? '' : '  ·  ${list[i].cellIndices.length} cell'}',
                          style: Bms.body(11, Bms.textFaint),
                        ),
                      ],
                    ),
                  ),
                  Text(list[i].severity.label,
                      style: Bms.body(10.5, Bms.severityColor(list[i].severity))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfigSheet extends ConsumerStatefulWidget {
  final BatteryConfig initial;
  const _ConfigSheet({required this.initial});

  @override
  ConsumerState<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends ConsumerState<_ConfigSheet> {
  late final Map<String, TextEditingController> _c;
  String? _error;

  static String _fmt(double? v, [int d = 3]) => v == null ? '' : v.toStringAsFixed(d);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _c = {
      'ovWarn': TextEditingController(text: _fmt(i.cellOverVoltWarnV)),
      'ovCrit': TextEditingController(text: _fmt(i.cellOverVoltCritV)),
      'uvWarn': TextEditingController(text: _fmt(i.cellUnderVoltWarnV)),
      'uvCrit': TextEditingController(text: _fmt(i.cellUnderVoltCritV)),
      'deltaWarn': TextEditingController(text: _fmt(i.deltaWarnMv, 0)),
      'deltaCrit': TextEditingController(text: _fmt(i.deltaCritMv, 0)),
      'devWarn': TextEditingController(text: _fmt(i.cellDeviationWarnMv, 0)),
      'devCrit': TextEditingController(text: _fmt(i.cellDeviationCritMv, 0)),
      'tempWarn': TextEditingController(text: _fmt(i.tempWarnC, 0)),
      'tempCrit': TextEditingController(text: _fmt(i.tempCritC, 0)),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String key) {
    final t = _c[key]!.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  bool _badInput() {
    // Ô điện áp có thể để trống (= tắt) nhưng nếu có chữ thì phải là số.
    for (final k in _c.keys) {
      final t = _c[k]!.text.trim();
      if (t.isNotEmpty && _num(k) == null) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (_badInput()) {
      setState(() => _error = 'Có ô không phải số hợp lệ.');
      return;
    }
    const d = BatteryConfig.defaults;
    final cfg = BatteryConfig(
      cellOverVoltWarnV: _num('ovWarn'),
      cellOverVoltCritV: _num('ovCrit'),
      cellUnderVoltWarnV: _num('uvWarn'),
      cellUnderVoltCritV: _num('uvCrit'),
      deltaWarnMv: _num('deltaWarn') ?? d.deltaWarnMv,
      deltaCritMv: _num('deltaCrit') ?? d.deltaCritMv,
      cellDeviationWarnMv: _num('devWarn') ?? d.cellDeviationWarnMv,
      cellDeviationCritMv: _num('devCrit') ?? d.cellDeviationCritMv,
      tempWarnC: _num('tempWarn') ?? d.tempWarnC,
      tempCritC: _num('tempCrit') ?? d.tempCritC,
    );
    final err = await ref.read(batteryHubProvider.notifier).updateConfig(cfg);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await ref.read(batteryHubProvider.notifier).resetConfig();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _field(String key, String label, String unit) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 10, bottom: 10),
          child: TextField(
            controller: _c[key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Bms.number(15),
            decoration: InputDecoration(
              labelText: label,
              suffixText: unit,
              labelStyle: Bms.body(12),
              suffixStyle: Bms.body(12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Bms.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Bms.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Bms.accent),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 6, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cấu hình ngưỡng cảnh báo', style: Bms.title(17)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                'Để trống ô điện áp = tắt kiểm tra đó. Hãy nhập theo thông số cell/BMS của nhà sản xuất — '
                'ứng dụng không tự đặt ngưỡng điện áp hoá học.',
                style: Bms.body(12),
              ),
            ),
            const SizedBox(height: 14),
            Text('Điện áp cell (V)', style: Bms.title(13)),
            const SizedBox(height: 8),
            Row(children: [
              _field('ovWarn', 'Quá áp WARNING', 'V'),
              _field('ovCrit', 'Quá áp CRITICAL', 'V'),
            ]),
            Row(children: [
              _field('uvWarn', 'Thấp áp WARNING', 'V'),
              _field('uvCrit', 'Thấp áp CRITICAL', 'V'),
            ]),
            Text('Cân bằng giữa các cell (mV)', style: Bms.title(13)),
            const SizedBox(height: 8),
            Row(children: [
              _field('deltaWarn', 'ΔV WARNING', 'mV'),
              _field('deltaCrit', 'ΔV CRITICAL', 'mV'),
            ]),
            Row(children: [
              _field('devWarn', 'Lệch TB WARNING', 'mV'),
              _field('devCrit', 'Lệch TB CRITICAL', 'mV'),
            ]),
            Text('Nhiệt độ pack/BMS (°C)', style: Bms.title(13)),
            const SizedBox(height: 8),
            Row(children: [
              _field('tempWarn', 'WARNING', '°C'),
              _field('tempCrit', 'CRITICAL', '°C'),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, right: 10),
                child: Text(_error!, style: Bms.body(12.5, Bms.critical)),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: _reset,
                  style: TextButton.styleFrom(foregroundColor: Bms.textDim),
                  child: const Text('Khôi phục mặc định'),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Bms.accent,
                      foregroundColor: Bms.bg,
                    ),
                    child: const Text('Lưu'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
