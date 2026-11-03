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
import 'activity_history.dart';
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

  // ---- Smart Key theo khoảng cách ----
  /// Đang bật chế độ giới hạn khoảng cách (mặc định BẬT, 2 m).
  final bool rangeStrict;
  final double rangeLimitM;

  /// Ước lượng khoảng cách (m) từ RSSI đã lọc; null nếu chưa có mẫu.
  final double? distanceM;

  /// RSSI đo ở mốc 2 m (null = chưa đo). Có cả 1 m và 2 m → chính xác hơn.
  final double? calibratedRssi2m;

  /// Hệ số suy hao đang dùng để quy đổi RSSI → mét.
  final double pathLossN;

  /// true = mốc 1 m là giá trị MẶC ĐỊNH tạm thời, chưa hiệu chỉnh.
  final bool provisional;

  /// Mốc đang đo hiệu chỉnh (1 hoặc 2).
  final int calibratingTargetM;

  /// Độ tin cậy 0..1 của khoảng cách ước lượng (heuristic, không phải xác suất).
  final double distanceConfidence;

  /// Ngưỡng vùng gần/xa theo mét (mặc định 1,8 m / 2,2 m quanh giới hạn 2 m).
  final double nearZoneM;
  final double farZoneM;

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
    this.rangeStrict = true,
    this.rangeLimitM = 2.0,
    this.distanceM,
    this.calibratedRssi2m,
    this.pathLossN = ProximityEngine.defaultPathLossN,
    this.provisional = true,
    this.calibratingTargetM = 1,
    this.distanceConfidence = 0,
    this.nearZoneM = 1.8,
    this.farZoneM = 2.2,
  });

  /// Đang trong bán kính (theo ước lượng). null nếu chưa biết.
  bool? get withinRange =>
      distanceM == null ? null : distanceM! <= rangeLimitM;
}

final proximityProvider =
    NotifierProvider<ProximityController, ProximitySnapshot>(
        ProximityController.new);

class ProximityController extends Notifier<ProximitySnapshot> {
  static const _kSens = 'prox_sensitivity';
  static const _kCal = 'prox_calibrated_rssi_1m';
  static const _kConfirm = 'prox_lock_confirm_s';
  static const _kCal2 = 'prox_calibrated_rssi_2m';
  static const _kStrict = 'prox_range_strict';
  static const _kRangeM = 'prox_range_m';

  final ProximityEngine _engine = ProximityEngine();
  int _sensitivity = 1;
  double? _cal;
  double? _cal2;
  bool _strict = true;
  double _rangeM = 2.0;
  int _calTarget = 1;
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
      _cal2 = p.getDouble(_kCal2);
      _strict = p.getBool(_kStrict) ?? true;
      _rangeM = (p.getDouble(_kRangeM) ?? 2.0).clamp(1.0, 3.0).toDouble();
      _confirm = (p.getInt(_kConfirm) ?? 5).clamp(3, 15);
      _publish(DateTime.now());
    } catch (_) {}
  }

  ProximityConfig _config(bool unlockOn, bool lockOn,
          {bool forceRange = false}) =>
      ProximityConfig(
        unlockEnabled: unlockOn,
        lockEnabled: lockOn,
        sensitivity: _sensitivity,
        calibratedRssi1m: _cal,
        legacyNearThreshold: _legacyNear,
        legacyFarThreshold: _legacyFar,
        lockConfirmSeconds: _confirm,
        rangeLimitM: (_strict || forceRange) ? _rangeM : null,
        calibratedRssi2m: _cal2,
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
    // Lưu bền để xem lại ở "Lịch sử hoạt động" (best-effort, không chặn UI).
    if (fresh.isNotEmpty) ActivityHistory.append(fresh.reversed.toList());
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
      rangeStrict: _strict,
      rangeLimitM: _rangeM,
      distanceM: _engine.filteredRssi == null
          ? null
          : _engine.estimateDistanceM(
              _config(unlockOn, lockOn, forceRange: true),
              _engine.filteredRssi!,
            ),
      calibratedRssi2m: _cal2,
      pathLossN: _engine.pathLossN(_config(unlockOn, lockOn)),
      provisional: _cal == null,
      calibratingTargetM: _calTarget,
      distanceConfidence:
          _engine.distanceConfidence(_config(unlockOn, lockOn), now),
      nearZoneM: (_rangeM - ProximityEngine.rangeZoneHalfWidthM)
          .clamp(0.5, 10.0)
          .toDouble(),
      farZoneM: _rangeM + ProximityEngine.rangeZoneHalfWidthM,
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
        if (cal.targetM == 2) {
          // Mốc 2 m phải yếu hơn mốc 1 m rõ rệt, nếu không là đo sai.
          if (_cal != null && cal.rssi1m! > _cal! - 1.0) {
            _calMsg = 'Mốc 2 m (${cal.rssi1m!.toStringAsFixed(1)} dBm) không '
                'yếu hơn mốc 1 m (${_cal!.toStringAsFixed(1)} dBm). '
                'Hãy đứng xa xe hơn (đúng ~2 m) rồi đo lại.';
          } else {
            _cal2 = cal.rssi1m;
            _saveDouble(_kCal2, _cal2!);
          }
        } else {
          _cal = cal.rssi1m;
          _saveDouble(_kCal, _cal!);
        }
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

  void startCalibration({int targetM = 1}) {
    _calMsg = null;
    _calTarget = targetM == 2 ? 2 : 1;
    _engine.startCalibration(DateTime.now(), targetM: _calTarget);
    _publish(DateTime.now());
  }

  // ---------- Smart Key giới hạn khoảng cách ----------
  Future<void> setRangeStrict(bool v) async {
    _strict = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_kStrict, v);
    } catch (_) {}
    BleLogger.instance.event('range_strict_changed', {'enabled': v});
    _publish(DateTime.now());
  }

  Future<void> setRangeLimitM(double m) async {
    _rangeM = m.clamp(1.0, 3.0).toDouble();
    await _saveDouble(_kRangeM, _rangeM);
    _publish(DateTime.now());
  }

  /// Kiểm tra bán kính cho thao tác TAY (nút Mở khóa / Bật xe). Nếu tắt chế độ
  /// khoảng cách thì luôn cho phép. Ghi nhật ký khi chặn.
  RangeCheck checkManualRange(String action) {
    final r = _engine.checkManualRange(_config(false, false), DateTime.now());
    if (!r.ok) {
      BleLogger.instance.event('range_gate_blocked', {
        'action': action,
        'distance_m': r.distanceM,
        'limit_m': _rangeM,
      });
    }
    return r;
  }

  Future<void> clearCalibration2m() async {
    _cal2 = null;
    _calMsg = 'Đã xóa mốc 2 m — quy đổi khoảng cách dùng hệ số mặc định.';
    try {
      (await SharedPreferences.getInstance()).remove(_kCal2);
    } catch (_) {}
    _publish(DateTime.now());
  }

  void cancelCalibration() {
    _engine.cancelCalibration();
    _calMsg = 'Đã hủy hiệu chỉnh.';
    _publish(DateTime.now());
  }

  Future<void> clearCalibration() async {
    _cal = null;
    _cal2 = null;
    _calMsg = 'Đã xóa hiệu chỉnh — dùng RSSI@1 m mặc định tạm thời.';
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kCal);
      await p.remove(_kCal2);
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
