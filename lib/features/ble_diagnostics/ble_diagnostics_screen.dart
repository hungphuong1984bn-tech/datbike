// Chẩn đoán Bluetooth (BLE) — trang chỉ-đọc cho giai đoạn 2.11.0.
//
// Hiển thị: trạng thái liên kết (tách "kết nối" khỏi "có dữ liệu"), bộ điều
// hợp, thiết bị + RSSI, bảng GATT (service/characteristic/thuộc tính), thống
// kê gói/lỗi, dữ liệu xe kèm độ mới, mức bằng chứng giao thức và xuất nhật ký.
//
// Trang này KHÔNG gửi lệnh nào tới xe và không đổi luồng kết nối.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/ble/ble_diag_stats.dart';
import '../../core/ble/ble_link_status.dart';
import '../../core/ble/ble_logger.dart';
import '../../core/ble/ble_permissions.dart';
import '../../core/ble/data_field.dart';
import '../../core/ble/log_export.dart';
import '../../core/ble/protocol_evidence.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';

enum _Range {
  m15('15 phút', Duration(minutes: 15)),
  h1('1 giờ', Duration(hours: 1)),
  d1('24 giờ', Duration(hours: 24)),
  all('Tất cả', null);

  const _Range(this.label, this.span);
  final String label;
  final Duration? span;
}

class _Export {
  const _Export(this.text, this.count, this.skipped);
  final String text;
  final int count;
  final int skipped;
}

class BleDiagnosticsScreen extends ConsumerStatefulWidget {
  const BleDiagnosticsScreen({super.key});

  @override
  ConsumerState<BleDiagnosticsScreen> createState() => _BleDiagnosticsScreenState();
}

class _BleDiagnosticsScreenState extends ConsumerState<BleDiagnosticsScreen> {
  Timer? _tick;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  BluetoothAdapterState? _adapter;
  BlePermissionResult? _perm;

  ExportPrivacy _privacy = ExportPrivacy.shareSafe;
  _Range _range = _Range.h1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      _adapterSub = FlutterBluePlus.adapterState.listen((s) {
        if (mounted) setState(() => _adapter = s);
      });
    } catch (_) {
      // Nền tảng không hỗ trợ BLE: để adapter = null (chưa biết).
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }

  // ───────────────────────── Suy ra trạng thái ─────────────────────────

  BleLinkStatus _status(BleState st, BleController ctrl, DateTime now) {
    final phase = st.phase;
    final connected = phase == BlePhase.connected;
    final connecting = phase == BlePhase.connecting;
    final flags = stageFlagsFor(connecting ? ctrl.currentConnectStage : null);
    final stats = BleDiagStats.instance;
    return deriveBleLinkStatus(BleLinkInputs(
      now: now,
      adapterOn: _adapter == null ? null : _adapter == BluetoothAdapterState.on,
      permissionGranted:
          _perm == null ? null : _perm == BlePermissionResult.granted,
      scanning: phase == BlePhase.scanning,
      gattConnecting: connecting && !flags.gattConnected,
      gattConnected: connected || (connecting && flags.gattConnected),
      servicesDiscovered: connected || flags.servicesDiscovered,
      authInProgress: connecting && flags.authInProgress,
      authorized: connected ? st.isAuthorized : flags.authDone,
      reconnecting: phase == BlePhase.reconnecting,
      everConnected: stats.connectedAt != null || stats.lastDisconnectAt != null,
      connectedAt: stats.connectedAt,
      lastDataAt: ctrl.lastTelemetryAt,
    ));
  }

  Color _sev(LinkSeverity s) {
    switch (s) {
      case LinkSeverity.neutral:
        return AppColors.textMuted;
      case LinkSeverity.ok:
        return AppColors.tertiary;
      case LinkSeverity.info:
        return AppColors.cyan;
      case LinkSeverity.warning:
        return AppColors.amber;
      case LinkSeverity.error:
        return AppColors.red;
    }
  }

  Color _fresh(Freshness f) {
    switch (f) {
      case Freshness.live:
        return AppColors.tertiary;
      case Freshness.stale:
        return AppColors.amber;
      case Freshness.cached:
        return AppColors.cyan;
      case Freshness.none:
        return AppColors.textMuted;
    }
  }

  // ───────────────────────── Định dạng ─────────────────────────

  String _t(DateTime? d) {
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _ago(DateTime? d, DateTime now) {
    if (d == null) return '—';
    final s = now.difference(d).inSeconds;
    if (s < 0) return _t(d);
    if (s < 60) return '${_t(d)} (${s}s trước)';
    if (s < 3600) return '${_t(d)} (${s ~/ 60} phút trước)';
    return '${_t(d)} (${s ~/ 3600} giờ trước)';
  }

  String _permLabel(BlePermissionResult r) {
    switch (r) {
      case BlePermissionResult.granted:
        return 'Đã cấp quyền';
      case BlePermissionResult.denied:
        return 'Bị từ chối';
      case BlePermissionResult.permanentlyDenied:
        return 'Bị từ chối vĩnh viễn (mở Cài đặt để bật)';
      case BlePermissionResult.locationServiceOff:
        return 'Dịch vụ Vị trí đang tắt';
    }
  }

  String _adapterLabel() {
    switch (_adapter) {
      case null:
        return 'Chưa biết';
      case BluetoothAdapterState.on:
        return 'Bật';
      case BluetoothAdapterState.off:
        return 'Tắt';
      case BluetoothAdapterState.unauthorized:
        return 'Chưa được cấp quyền';
      case BluetoothAdapterState.unavailable:
        return 'Không hỗ trợ Bluetooth';
      default:
        return _adapter!.name;
    }
  }

  // ───────────────────────── Thành phần giao diện ─────────────────────────

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: Text(k, style: AppTypography.bodySm())),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: AppTypography.bodyMd(color: color)),
            ),
          ],
        ),
      );

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: AppTypography.labelSm(color: c)),
      );

  Widget _card(Widget child, {Color? accent}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        child: GlassCard(accent: accent, child: child),
      );

  Widget _statusCard(BleLinkStatus s, BleState st) {
    final c = _sev(s.severity);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bluetooth_rounded, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(s.label, style: AppTypography.headlineSm(color: c))),
          ]),
          const SizedBox(height: 6),
          Text(s.hint, style: AppTypography.bodyMd()),
          if (st.message != null && st.message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(st.message!, style: AppTypography.bodySm()),
          ],
          const SizedBox(height: 8),
          Text(
            s.hasLiveData
                ? 'Có dữ liệu trực tiếp.'
                : 'KHÔNG có dữ liệu trực tiếp: mọi số liệu bên dưới (nếu có) đều là số liệu cũ.',
            style: AppTypography.labelMd(
                color: s.hasLiveData ? AppColors.tertiary : AppColors.amber),
          ),
        ],
      ),
      accent: c,
    );
  }

  Widget _adapterCard(BleState st, DateTime now) {
    final q = signalQualityFromRssi(st.filteredRssi ?? st.rssi);
    final dev = st.device;
    return _card(Column(children: [
      _kv('Bluetooth điện thoại', _adapterLabel()),
      _kv('Quyền',
          _perm == null ? 'Chưa kiểm tra' : _permLabel(_perm!)),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () async {
            final r = await BlePermissions.check();
            if (mounted) setState(() => _perm = r);
          },
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: const Text('Kiểm tra quyền'),
        ),
      ),
      const Divider(height: 16),
      _kv('Thiết bị', st.bikeName ?? dev?.platformName ?? 'Chưa chọn'),
      _kv('Mã thiết bị (remoteId)', dev?.remoteId.str ?? '—'),
      _kv('RSSI', st.rssi == null ? '—' : '${st.rssi} dBm'),
      _kv('RSSI đã lọc',
          st.filteredRssi == null ? '—' : '${st.filteredRssi} dBm'),
      _kv('Chất lượng tín hiệu', signalQualityLabel(q)),
      _kv('Lần thử kết nối lại', '${st.reconnectAttempt}'),
      _kv('Xác thực (theo trạng thái ứng dụng)',
          st.isAuthorized ? 'Đã xác thực' : 'Chưa xác thực'),
    ]));
  }

  Widget _statsCard(DateTime now) {
    final s = BleDiagStats.instance;
    final avg = s.averagePacketIntervalMs;
    final rate = s.errorRate;
    return _card(Column(children: [
      _kv('Gói nhận được', '${s.packetsReceived}'),
      for (final e in s.packetsByKind.entries) _kv('  · ${e.key}', '${e.value}'),
      _kv('Lỗi giải mã/đọc gói', '${s.packetErrors}',
          color: s.packetErrors > 0 ? AppColors.amber : null),
      _kv('Tỷ lệ lỗi',
          rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%'),
      _kv('Chu kỳ gói trung bình',
          avg == null ? '—' : '${avg.toStringAsFixed(0)} ms'),
      _kv('Gói gần nhất', _ago(s.lastPacketAt, now)),
      const Divider(height: 16),
      _kv('Số lần thử kết nối', '${s.connectAttempts}'),
      _kv('Kết nối thất bại', '${s.connectFailures}',
          color: s.connectFailures > 0 ? AppColors.amber : null),
      _kv('Kết nối từ lúc', _t(s.connectedAt)),
      _kv('Mất kết nối gần nhất', _ago(s.lastDisconnectAt, now)),
      _kv('Số lần ngắt (ngoài ý muốn)',
          '${s.disconnects} (${s.unexpectedDisconnects})'),
      _kv('Xác thực quan sát', s.auth.label),
      if (s.lastFailureKind != null)
        _kv('Lỗi kết nối gần nhất',
            '${s.lastFailureStage ?? '?'} · ${s.lastFailureKind}'
            '${s.lastFailureCode != null ? ' · mã ${s.lastFailureCode}' : ''}'),
      if (s.lastErrorDetail != null) _kv('Chi tiết lỗi gói', s.lastErrorDetail!),
      const Divider(height: 16),
      if (s.notifyResults.isEmpty)
        _kv('Đăng ký notify', 'Chưa có kết quả')
      else
        for (final e in s.notifyResults.entries)
          _kv('Notify ${e.key.substring(0, 8)}…', e.value.outcome.label),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(BleDiagStats.instance.reset),
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Đặt lại bộ đếm'),
        ),
      ),
    ]));
  }

  Widget _gattCard(BleState st) {
    if (st.characteristics.isEmpty) {
      return _card(Text(
        'Chưa có danh sách dịch vụ (chưa khám phá được hoặc chưa kết nối).',
        style: AppTypography.bodyMd(),
      ));
    }
    final byService = <String, List<BluetoothCharacteristic>>{};
    for (final c in st.characteristics) {
      byService
          .putIfAbsent(c.serviceUuid.str128.toLowerCase(), () => [])
          .add(c);
    }
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in byService.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: SelectableText('Service ${e.key}',
                style: AppTypography.labelMd(color: AppColors.primary)),
          ),
          for (final c in e.value)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(c.uuid.str128.toLowerCase(),
                      style: AppTypography.bodySm()),
                  Text(
                    [
                      if (c.properties.read) 'Read',
                      if (c.properties.write) 'Write',
                      if (c.properties.writeWithoutResponse) 'WriteNoResp',
                      if (c.properties.notify) 'Notify',
                      if (c.properties.indicate) 'Indicate',
                    ].join(' · '),
                    style: AppTypography.labelSm(),
                  ),
                ],
              ),
            ),
        ],
      ],
    ));
  }

  String _fmt(String label, String unit, double v) {
    final digits = unit == 'cell'
        ? 0
        : (unit == 'V' && label.contains('Cell'))
            ? 3
            : (unit == 'V' ? 2 : 1);
    return v.toStringAsFixed(digits);
  }

  Widget _fieldRow(
      String label, DataField<double> f, DateTime now, Duration window) {
    final fr = f.freshness(now, window);
    final shown = f.hasValue && f.valid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: AppTypography.bodyMd())),
            Text(
              shown ? '${_fmt(label, f.unit, f.value!)} ${f.unit}' : '—',
              style: AppTypography.bodyMd(
                  color: shown && fr == Freshness.live ? null : AppColors.textMuted),
            ),
            const SizedBox(width: 8),
            _chip(fr.label, _fresh(fr)),
          ]),
          Text(
            f.hasValue
                ? '${f.source.label} · nhận ${_t(f.receivedAt)}'
                    '${!f.valid && f.invalidReason != null ? ' · KHÔNG hợp lệ: ${f.invalidReason}' : ''}'
                : 'Chưa nhận được',
            style: AppTypography.labelSm(),
          ),
        ],
      ),
    );
  }

  Widget _dataCard(BleState st, BleController ctrl, BleLinkStatus link, DateTime now) {
    final live = link.isLinkUp;
    final tel = st.lastTelemetry;
    final tAt = ctrl.lastTelemetryAt;
    final tf = (tel != null && tAt != null)
        ? TelemetryFields.fromBike(tel, tAt,
            source: live ? FieldSource.bleDashboard : FieldSource.cache)
        : TelemetryFields.empty;
    final bat = st.lastBattery;
    final bAt = st.lastBatteryAt;
    final bf = (bat != null && bAt != null)
        ? BatteryFields.fromMsg(bat, bAt,
            source: live ? FieldSource.bleBatteryLog : FieldSource.cache)
        : BatteryFields.empty;
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dashboard xe (cửa sổ “mới”: ${kDashboardFreshWindow.inSeconds}s)',
            style: AppTypography.labelLg()),
        for (final e in tf.entries) _fieldRow(e.key, e.value, now, kDashboardFreshWindow),
        const Divider(height: 20),
        Text('Log BMS (cửa sổ “mới”: ${kBatteryFreshWindow.inSeconds}s)',
            style: AppTypography.labelLg()),
        for (final e in bf.entries) _fieldRow(e.key, e.value, now, kBatteryFreshWindow),
        const SizedBox(height: 6),
        Text(
          'Giá trị 0 ở một số trường được đánh dấu không hợp lệ vì giao thức không '
          'phân biệt “xe không gửi” với “bằng 0”. Dòng pha là dòng pha động cơ, '
          'không phải dòng pin.',
          style: AppTypography.labelSm(),
        ),
      ],
    ));
  }

  Widget _evidenceCard() {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chỉ mức “Có vector capture thật” mới được coi là đã xác minh. '
          'Chưa có mục nào ở đây được kiểm thử tự động trên xe thật.',
          style: AppTypography.bodySm(),
        ),
        const SizedBox(height: 8),
        for (final e in kProtocolEvidence)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(e.title, style: AppTypography.bodyMd())),
                  _chip(
                    e.level.label,
                    e.level.isVerified
                        ? AppColors.tertiary
                        : (e.level == EvidenceLevel.hypothesis
                            ? AppColors.red
                            : AppColors.amber),
                  ),
                ]),
                Text(e.basis, style: AppTypography.labelSm()),
                if (e.controlRelated)
                  Text('Liên quan lệnh điều khiển xe', style: AppTypography.labelSm(color: AppColors.amber)),
              ],
            ),
          ),
      ],
    ));
  }

  // ───────────────────────── Xuất nhật ký ─────────────────────────

  Future<String> _readTail(File f, {int cap = 8 * 1024 * 1024}) async {
    final len = await f.length();
    final raf = await f.open();
    try {
      final start = len > cap ? len - cap : 0;
      await raf.setPosition(start);
      final bytes = await raf.read(len - start);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await raf.close();
    }
  }

  Future<_Export> _build({required bool csv}) async {
    final from =
        _range.span == null ? null : DateTime.now().subtract(_range.span!);
    final files = (await BleLogger.listSessions())
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList();
    final all = <LogEntry>[];
    var bad = 0;
    var used = 0;
    for (final f in files) {
      if (used >= 6) break;
      if (from != null && (await f.lastModified()).isBefore(from)) continue;
      final parsed = LogExporter.parseJsonl(await _readTail(f));
      all.addAll(parsed.entries);
      bad += parsed.badLines;
      used++;
    }
    all.sort((a, b) => a.ts.compareTo(b.ts));
    final filtered = LogExporter.filterByTime(all, from: from);
    final text = csv
        ? LogExporter.toCsv(filtered, privacy: _privacy)
        : LogExporter.toJson(filtered,
            privacy: _privacy, appBuild: appBuild, from: from, badLines: bad);
    return _Export(text, filtered.length, bad);
  }

  Future<bool> _confirmFull() async {
    if (_privacy == ExportPrivacy.shareSafe) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xuất nhật ký đầy đủ?'),
        content: const Text(
            'Bản đầy đủ có thể chứa dữ liệu gói thô. Chỉ gửi cho người bạn tin cậy.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Tiếp tục')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _export({required bool csv, required bool share}) async {
    if (_busy) return;
    if (share && !await _confirmFull()) return;
    setState(() => _busy = true);
    try {
      final e = await _build(csv: csv);
      if (!mounted) return;
      if (e.count == 0) {
        showAppSnack(context, 'Không có nhật ký trong khoảng thời gian này.',
            kind: SnackKind.warning);
        return;
      }
      if (share) {
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now()
            .toIso8601String()
            .substring(0, 19)
            .replaceAll(':', '')
            .replaceAll('-', '');
        final f = File('${dir.path}/thbike_ble_log_$ts.${csv ? 'csv' : 'json'}');
        await f.writeAsString(e.text, flush: true);
        await SharePlus.instance.share(ShareParams(
            files: [XFile(f.path)], text: 'Nhật ký BLE — THBIKE'));
      } else {
        if (e.text.length > 400000) {
          showAppSnack(context,
              'Nhật ký quá lớn để sao chép (${e.count} dòng). Hãy dùng “Chia sẻ” hoặc chọn khoảng thời gian ngắn hơn.',
              kind: SnackKind.warning);
          return;
        }
        await Clipboard.setData(ClipboardData(text: e.text));
        if (!mounted) return;
        showAppSnack(context,
            'Đã sao chép ${e.count} dòng${e.skipped > 0 ? ' (bỏ qua ${e.skipped} dòng hỏng)' : ''}.',
            kind: SnackKind.success);
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Không xuất được nhật ký. Thử khoảng thời gian ngắn hơn.',
            kind: SnackKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyStats(BleState st, BleLinkStatus link) async {
    final doc = const JsonEncoder.withIndent('  ').convert({
      'build': appBuild,
      'phase': st.phase.name,
      'link': link.name,
      'hasLiveData': link.hasLiveData,
      'stats': BleDiagStats.instance.toJson(),
    });
    await Clipboard.setData(ClipboardData(text: doc));
    if (!mounted) return;
    showAppSnack(context, 'Đã sao chép thống kê chẩn đoán.', kind: SnackKind.success);
  }

  Widget _exportCard(BleState st, BleLinkStatus link) {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Khoảng thời gian', style: AppTypography.labelMd()),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          for (final r in _Range.values)
            ChoiceChip(
              label: Text(r.label),
              selected: _range == r,
              onSelected: (_) => setState(() => _range = r),
            ),
        ]),
        const SizedBox(height: 10),
        Text('Mức riêng tư', style: AppTypography.labelMd()),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          for (final p in ExportPrivacy.values)
            ChoiceChip(
              label: Text(p == ExportPrivacy.shareSafe ? 'An toàn để chia sẻ' : 'Đầy đủ'),
              selected: _privacy == p,
              onSelected: (_) => setState(() => _privacy = p),
            ),
        ]),
        const SizedBox(height: 4),
        Text(_privacy.label, style: AppTypography.labelSm()),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _export(csv: false, share: false),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Sao chép JSON'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _export(csv: true, share: false),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Sao chép CSV'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _export(csv: false, share: true),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Chia sẻ JSON'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _export(csv: true, share: true),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Chia sẻ CSV'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copyStats(st, link),
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: const Text('Sao chép thống kê'),
          ),
        ]),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(),
          ),
      ],
    ));
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(bleProvider);
    final ctrl = ref.read(bleProvider.notifier);
    final now = DateTime.now();
    final link = _status(st, ctrl, now);

    return DsScaffold(
      title: 'Chẩn đoán Bluetooth',
      subtitle: 'Kết nối, gói dữ liệu, bằng chứng giao thức',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: AppSpacing.md),
          _statusCard(link, st),
          const DsSectionHeader('Bộ điều hợp và thiết bị',
              hint: 'Trạng thái Bluetooth điện thoại, thiết bị và tín hiệu'),
          _adapterCard(st, now),
          const DsSectionHeader('Thống kê gói và lỗi',
              hint: 'Đếm từ lúc mở ứng dụng, không lưu qua lần khởi động sau'),
          _statsCard(now),
          const DsSectionHeader('Dịch vụ GATT',
              hint: 'Service, characteristic và thuộc tính đọc/ghi/notify'),
          _gattCard(st),
          const DsSectionHeader('Dữ liệu xe và độ mới',
              hint: 'Mỗi giá trị có đơn vị, nguồn, thời điểm nhận và trạng thái hợp lệ'),
          _dataCard(st, ctrl, link, now),
          const DsSectionHeader('Mức bằng chứng giao thức',
              hint: 'Điều gì đã có vector thật, điều gì chỉ theo tài liệu'),
          _evidenceCard(),
          const DsSectionHeader('Xuất nhật ký',
              hint: 'Lọc theo thời gian, che dữ liệu nhạy cảm, chia sẻ để chẩn đoán'),
          _exportCard(st, link),
        ],
      ),
    );
  }
}
