// Nối bleProvider và batteryHubProvider (CHỈ ĐỌC) với DiagLog.
// Không gửi lệnh nào xuống xe/BMS. Không ghi khóa phiên, token hay dữ liệu xác thực.
// Chạy nền từ main.dart để lịch sử lỗi không bị mất khi người dùng ở màn khác.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../battery/cell_model.dart' show BmsFreshness;
import '../battery/battery_hub.dart';
import '../battery/cell_protection_engine.dart';
import '../ble/ble_controller.dart';
import '../proto/bike_log.dart';
import '../services/battery_diagnostics_service.dart';
import 'diag_model.dart';

const String kDiagLogKey = 'diag_log_v1';

class DiagCenter extends Notifier<int> {
  final DiagLog log = DiagLog();

  bool _loaded = false;
  bool _wasConnected = false;
  Timer? _saveTimer;
  DateTime _lastEval = DateTime.fromMillisecondsSinceEpoch(0);

  // Trạng thái trước đó để chỉ ghi nhật ký khi có THAY ĐỔI thật.
  BikeState? _prevState;
  bool? _prevLocked;
  bool? _prevCharging;

  @override
  int build() {
    ref.onDispose(() => _saveTimer?.cancel());
    _load();

    ref.listen<BlePhase>(bleProvider.select((s) => s.phase), (prev, next) => _onPhase(prev, next));
    ref.listen<bool>(
      bleProvider.select((s) => s.dashboardEncrypted),
      (_, next) => _onEncrypted(next),
    );
    ref.listen<BikeLogMsg?>(
      bleProvider.select((s) => s.lastTelemetry),
      (_, next) => _onTelemetry(next),
    );
    ref.listen<ProtectionReport>(
      batteryHubProvider.select((s) => s.report),
      (_, next) => _onBmsReport(next),
    );
    ref.listen<bool>(
      bleProvider.select((s) => s.isLocked),
      (prev, next) => _onLocked(prev, next),
    );
    return 0;
  }

  // ── Lưu / nạp ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Sự kiện phát sinh trước khi nạp xong được giữ lại, đặt lên đầu.
      final fresh = log.events.reversed.toList();
      log.load(prefs.getString(kDiagLogKey));
      log.closeStaleOnStartup(DateTime.now());
      for (final e in fresh) {
        log.add(e);
      }
      _bump();
    } catch (_) {
      // Không đọc được bộ nhớ → vẫn chạy với nhật ký rỗng.
    }
  }

  void _bump() {
    state = state + 1;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDiagLogKey, log.encode());
    } catch (_) {}
  }

  /// Xóa toàn bộ nhật ký chẩn đoán (theo yêu cầu người dùng).
  Future<void> clearAll() async {
    log.clearAll();
    _bump();
    await _save();
  }

  // ── Bluetooth ────────────────────────────────────────────────────────────
  void _onPhase(BlePhase? prev, BlePhase next) {
    final now = DateTime.now();
    switch (next) {
      case BlePhase.connected:
        log.clear('ble:link', now);
        log.add(DiagEvent(
          id: 'ble:${now.microsecondsSinceEpoch}',
          at: now,
          source: DiagSource.ble,
          severity: DiagSeverity.info,
          title: 'Đã kết nối xe',
        ));
        _wasConnected = true;
      case BlePhase.reconnecting:
      case BlePhase.disconnected:
        if (_wasConnected) {
          final attempt = ref.read(bleProvider).reconnectAttempt;
          log.raise(DiagEvent(
            id: 'ble:link',
            at: now,
            source: DiagSource.ble,
            severity: DiagSeverity.warning,
            isIssue: true,
            title: 'Mất kết nối Bluetooth với xe',
            detail: next == BlePhase.reconnecting
                ? 'Đang thử kết nối lại${attempt > 0 ? ' (lần $attempt)' : ''}.'
                : 'Đã ngắt kết nối.',
            cause: 'Xe ở ngoài tầm sóng, xe tắt/ngủ, hoặc Bluetooth điện thoại bị tắt.',
            advice: 'Đến gần xe, bật Bluetooth rồi để ứng dụng tự kết nối lại hoặc kết nối thủ công.',
          ));
          log.add(DiagEvent(
            id: 'ble:${now.microsecondsSinceEpoch}',
            at: now,
            source: DiagSource.ble,
            severity: DiagSeverity.warning,
            title: next == BlePhase.reconnecting ? 'Đang kết nối lại' : 'Đã ngắt kết nối',
          ));
          _wasConnected = false;
          // Mất kết nối: mọi lỗi từ xe/BMS không còn được xác nhận trực tiếp.
          log.clearMissing('vehicle:', const {}, now);
          log.clearMissing('bms:', const {}, now);
          _prevState = null;
          _prevCharging = null;
        }
      case BlePhase.connecting:
        log.add(DiagEvent(
          id: 'ble:${now.microsecondsSinceEpoch}',
          at: now,
          source: DiagSource.ble,
          severity: DiagSeverity.info,
          title: 'Đang kết nối xe',
        ));
      case BlePhase.idle:
      case BlePhase.scanning:
        return;
    }
    _bump();
  }

  void _onEncrypted(bool encrypted) {
    final now = DateTime.now();
    final changed = encrypted
        ? log.raise(DiagEvent(
            id: 'ble:decode',
            at: now,
            source: DiagSource.ble,
            severity: DiagSeverity.warning,
            isIssue: true,
            title: 'Chưa giải mã được dữ liệu xe',
            detail: 'Gói dữ liệu từ xe liên tục không đọc được.',
            cause: 'Phiên xác thực với xe chưa hợp lệ hoặc đã hết hạn.',
            advice: 'Ngắt kết nối rồi kết nối lại xe để xác thực lại phiên.',
          ))
        : log.clear('ble:decode', now);
    if (changed) _bump();
  }

  // ── Xe ───────────────────────────────────────────────────────────────────
  void _onLocked(bool? prev, bool next) {
    if (prev == null || prev == next || _prevLocked == next) return;
    _prevLocked = next;
    final now = DateTime.now();
    log.add(DiagEvent(
      id: 'act:${now.microsecondsSinceEpoch}',
      at: now,
      source: DiagSource.activity,
      severity: DiagSeverity.info,
      title: next ? 'Đã bật khóa chống trộm' : 'Đã mở khóa chống trộm',
    ));
    _bump();
  }

  void _onTelemetry(BikeLogMsg? t) {
    if (t == null) return;
    final now = DateTime.now();
    final ble = ref.read(bleProvider);
    if (ble.phase != BlePhase.connected) return;
    var changed = false;

    // Nhật ký hoạt động: chỉ khi trạng thái ĐỔI.
    if (_prevState != null && _prevState != t.state) {
      log.add(DiagEvent(
        id: 'act:${now.microsecondsSinceEpoch}',
        at: now,
        source: DiagSource.activity,
        severity: DiagSeverity.info,
        title: 'Xe chuyển trạng thái: ${t.drivingModeLabel}',
      ));
      changed = true;
    }
    _prevState = t.state;

    final charging = t.charging != null;
    if (_prevCharging != null && _prevCharging != charging) {
      log.add(DiagEvent(
        id: 'act:${now.microsecondsSinceEpoch + 1}',
        at: now,
        source: DiagSource.activity,
        severity: DiagSeverity.info,
        title: charging ? 'Bắt đầu sạc' : 'Kết thúc sạc',
        detail: 'Pin ${t.percent}%',
      ));
      changed = true;
    }
    _prevCharging = charging;

    // Đánh giá lỗi: giới hạn 1 lần / 3 giây để không tốn pin.
    if (now.difference(_lastEval) >= const Duration(seconds: 3)) {
      _lastEval = now;
      changed = _evaluateVehicle(t, now) || changed;
    }
    if (changed) _bump();
  }

  bool _evaluateVehicle(BikeLogMsg t, DateTime now) {
    final ble = ref.read(bleProvider);
    final hub = ref.read(batteryHubProvider);
    final fresh = hub.freshness == BmsFreshness.live;
    final report = BatteryDiagnosticsService.analyze(
      telemetry: t,
      battery: fresh ? ble.lastBattery : null,
      modelName: ble.bikeName,
    );

    final keep = <String>{};
    var changed = false;

    if (report.hasLiveTelemetry) {
      for (final item in report.obdItems) {
        if (item.isHealthy) continue;
        final id = 'vehicle:obd:${item.id}';
        keep.add(id);
        changed = log.raise(DiagEvent(
              id: id,
              at: now,
              source: DiagSource.vehicle,
              severity: item.severity == 'Khẩn cấp' ? DiagSeverity.critical : DiagSeverity.warning,
              isIssue: true,
              title: item.name,
              detail: t.error != 0 ? 'Mã lỗi xe: ${t.error}' : 'Mã chẩn đoán: ${item.code}',
              cause: item.description,
              advice: item.recommendation,
            )) ||
            changed;
      }

      // Xe báo mã lỗi nhưng không khớp mục chẩn đoán nào → ghi đúng mã, không diễn giải.
      if (t.error != 0 && keep.isEmpty) {
        final id = 'vehicle:error:${t.error}';
        keep.add(id);
        changed = log.raise(DiagEvent(
              id: id,
              at: now,
              source: DiagSource.vehicle,
              severity: DiagSeverity.warning,
              isIssue: true,
              title: 'Xe báo mã lỗi ${t.error}',
              detail: 'Ứng dụng chưa có mô tả cho mã này.',
              cause: 'Bộ điều khiển xe báo mã lỗi ${t.error}. Ứng dụng không có bảng mô tả chính thức nên không suy đoán nguyên nhân.',
              advice: 'Dừng xe ở nơi an toàn, tắt rồi bật lại xe. Nếu mã vẫn xuất hiện, ghi lại mã và liên hệ trạm dịch vụ Dat Bike.',
            )) ||
            changed;
      }

      if (t.isSideStandDown && t.isBikeOn) {
        const id = 'vehicle:sidestand';
        keep.add(id);
        changed = log.raise(DiagEvent(
              id: id,
              at: now,
              source: DiagSource.vehicle,
              severity: DiagSeverity.info,
              isIssue: true,
              title: 'Chân chống đang hạ',
              cause: 'Cảm biến chân chống báo chân chống chưa gạt lên.',
              advice: 'Gạt chân chống lên hết trước khi di chuyển.',
            )) ||
            changed;
      }
    }

    final n = log.clearMissing('vehicle:', keep, now);
    return changed || n > 0;
  }

  // ── BMS ──────────────────────────────────────────────────────────────────
  void _onBmsReport(ProtectionReport r) {
    final now = DateTime.now();
    // Chỉ ghi nhận khi dữ liệu BMS là trực tiếp; dữ liệu cũ không được coi như đang đo.
    if (!r.evaluatedLive) return;
    final keep = <String>{};
    var changed = false;
    for (final a in r.alerts) {
      if (a.severity == AlertSeverity.normal) continue;
      final id = 'bms:${a.id}';
      keep.add(id);
      changed = log.raise(DiagEvent(
            id: id,
            at: a.since,
            source: DiagSource.bms,
            severity: a.severity == AlertSeverity.critical ? DiagSeverity.critical : DiagSeverity.warning,
            isIssue: true,
            title: a.title,
            detail: [
              if (a.measured.isNotEmpty) a.measured,
              if (a.cellIndices.isNotEmpty) a.cellLabels,
            ].join(' · '),
            cause: a.cause,
            advice: a.recommendation,
          )) ||
          changed;
    }
    final n = log.clearMissing('bms:', keep, now);
    if (changed || n > 0) _bump();
  }
}

final diagProvider = NotifierProvider<DiagCenter, int>(DiagCenter.new);
