// ProximityController — cầu nối giữa ProximityEngine (logic thuần) và app.
//
// KHÔNG import ble_controller.dart (tránh vòng phụ thuộc). BleController gọi
// vào đây mỗi chu kỳ đo RSSI và tự thực thi lệnh trả về; sau đó báo lại kết
// quả bằng [reportResult]. Cờ bật/tắt (walkUpUnlock / autoLockWalkAway) vẫn
// nằm trong BleState như trước — controller này chỉ giữ độ nhạy, hiệu chỉnh
// và trạng thái hiển thị.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_logger.dart';
import 'proximity_engine.dart';

class ProximitySnapshot {
  final ProximityStatus status;
  final String message;
  final ProximityZone zone;
  final double? rawRssi;
  final double? filteredRssi;
  final double unlockThreshold;
  final double lockThreshold;
  final bool calibrated;
  final double? calibratedRssi1m;
  final int sensitivity;
  final int lockConfirmSeconds;
  final bool calibrating;
  final double calibrationProgress;
  final String? calibrationMessage;
  final bool unlockArmed;
  final bool lockArmed;
  final List<ProximityEvent> events;

  const ProximitySnapshot({
    this.status = ProximityStatus.off,
    this.message = 'Chưa kết nối xe.',
    this.zone = ProximityZone.unknown,
    this.rawRssi,
    this.filteredRssi,
    this.unlockThreshold = -55.0,
    this.lockThreshold = -83.0,
    this.calibrated = false,
    this.calibratedRssi1m,
    this.sensitivity = 1,
    this.lockConfirmSeconds = 5,
    this.calibrating = false,
    this.calibrationProgress = 0,
    this.calibrationMessage,
    this.unlockArmed = true,
    this.lockArmed = false,
    this.events = const [],
  });
}

final proximityProvider =
    NotifierProvider<ProximityController, ProximitySnapshot>(
        ProximityController.new);

class ProximityController extends Notifier<ProximitySnapshot> {
  static const _kSens = 'prox_sensitivity';
  static const _kCal = 'prox_calibrated_rssi_1m';
  static const _kConfirm = 'prox_lock_confirm_s';

  final ProximityEngine _engine = ProximityEngine();
  int _sensitivity = 1;
  double? _cal;
  int _confirm = 5;
  String? _calMsg;
  ProximityEvent? _lastLogged;
  double _legacyNear = -55.0;
  double _legacyFar = -83.0;

  @override
  ProximitySnapshot build() {
    _load();
    return const ProximitySnapshot();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _sensitivity = (p.getInt(_kSens) ?? 1).clamp(0, 2);
      _cal = p.getDouble(_kCal);
      _confirm = (p.getInt(_kConfirm) ?? 5).clamp(3, 15);
      _publish(DateTime.now());
    } catch (_) {}
  }

  ProximityConfig _config(bool unlockOn, bool lockOn) => ProximityConfig(
        unlockEnabled: unlockOn,
        lockEnabled: lockOn,
        sensitivity: _sensitivity,
        calibratedRssi1m: _cal,
        legacyNearThreshold: _legacyNear,
        legacyFarThreshold: _legacyFar,
        lockConfirmSeconds: _confirm,
      );

  void _publish(DateTime now, {bool unlockOn = false, bool lockOn = false}) {
    final cfg = _config(unlockOn, lockOn);
    // Ghi log các sự kiện mới của engine ra nhật ký BLE (đã che dữ liệu nhạy cảm).
    final ev = _engine.events;
    final fresh = <ProximityEvent>[];
    for (var i = ev.length - 1; i >= 0; i--) {
      if (identical(ev[i], _lastLogged)) break;
      fresh.add(ev[i]);
    }
    for (final e in fresh.reversed) {
      BleLogger.instance.event('proximity_${e.kind}', {'detail': e.detail});
    }
    if (ev.isNotEmpty) _lastLogged = ev.last;

    state = ProximitySnapshot(
      status: _engine.status,
      message: _engine.message,
      zone: _engine.zone,
      rawRssi: _engine.rawRssi,
      filteredRssi: _engine.filteredRssi,
      unlockThreshold: _engine.unlockThreshold(cfg),
      lockThreshold: _engine.lockThreshold(cfg),
      calibrated: _cal != null,
      calibratedRssi1m: _cal,
      sensitivity: _sensitivity,
      lockConfirmSeconds: _confirm,
      calibrating: _engine.calibrating,
      calibrationProgress: _engine.calibrationProgress(now) ?? 0,
      calibrationMessage: _calMsg,
      unlockArmed: _engine.unlockArmed,
      lockArmed: _engine.lockArmed,
      events: ev.reversed.take(30).toList(),
    );
  }

  /// BleController gọi mỗi chu kỳ đo RSSI. Trả về quyết định (chưa thực thi).
  ProximityDecision onSample({
    required double rssi,
    required bool unlockEnabled,
    required bool lockEnabled,
    required double legacyNear,
    required double legacyFar,
    required ProximityContext ctx,
  }) {
    final now = DateTime.now();
    _legacyNear = legacyNear;
    _legacyFar = legacyFar;
    _engine.addSample(rssi, now);

    final cal = _engine.pollCalibration(now);
    if (cal != null) {
      _calMsg = cal.message;
      if (cal.ok && cal.rssi1m != null) {
        _cal = cal.rssi1m;
        _saveDouble(_kCal, _cal!);
      }
    }
    final d = _engine.evaluate(_config(unlockEnabled, lockEnabled), ctx, now);
    _publish(now, unlockOn: unlockEnabled, lockOn: lockEnabled);
    return d;
  }

  void reportResult(ProximityAction a, bool ok, String detail,
      {required bool unlockEnabled, required bool lockEnabled}) {
    final now = DateTime.now();
    _engine.reportResult(a, ok, now, detail);
    _publish(now, unlockOn: unlockEnabled, lockOn: lockEnabled);
  }

  void noteUserCommand({required bool locked}) =>
      _engine.noteUserCommand(DateTime.now(), locked: locked);

  void resetLink(String why) {
    _engine.resetLink(DateTime.now(), why: why);
    _publish(DateTime.now());
  }

  // ---------- Cài đặt / hiệu chỉnh ----------
  Future<void> setSensitivity(int v) async {
    _sensitivity = v.clamp(0, 2);
    await _saveInt(_kSens, _sensitivity);
    _publish(DateTime.now());
  }

  Future<void> setLockConfirmSeconds(int v) async {
    _confirm = v.clamp(3, 15);
    await _saveInt(_kConfirm, _confirm);
    _publish(DateTime.now());
  }

  void startCalibration() {
    _calMsg = null;
    _engine.startCalibration(DateTime.now());
    _publish(DateTime.now());
  }

  void cancelCalibration() {
    _engine.cancelCalibration();
    _calMsg = 'Đã hủy hiệu chỉnh.';
    _publish(DateTime.now());
  }

  Future<void> clearCalibration() async {
    _cal = null;
    _calMsg = 'Đã xóa hiệu chỉnh — dùng ngưỡng cũ.';
    try {
      (await SharedPreferences.getInstance()).remove(_kCal);
    } catch (_) {}
    _publish(DateTime.now());
  }

  Future<void> _saveInt(String k, int v) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(k, v);
    } catch (_) {}
  }

  Future<void> _saveDouble(String k, double v) async {
    try {
      await (await SharedPreferences.getInstance()).setDouble(k, v);
    } catch (_) {}
  }
}
