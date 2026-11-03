// Kiểm thử máy trạng thái Smart Key (logic thuần, dữ liệu do test dựng).

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/proximity/proximity_engine.dart';
import 'package:mybike_app/core/proximity/smart_key_state.dart';

SmartKeyInput _in({
  bool bt = true,
  bool perm = true,
  bool connected = true,
  bool connecting = false,
  bool ever = true,
  bool auth = true,
  bool fault = false,
  bool locked = true,
  bool on = false,
  ProximityZone zone = ProximityZone.near,
  double? speed = 0,
  bool fresh = true,
}) =>
    SmartKeyInput(
      bluetoothOn: bt,
      permissionGranted: perm,
      connected: connected,
      connecting: connecting,
      everConnected: ever,
      authorized: auth,
      securityFault: fault,
      bikeLocked: locked,
      bikeOn: on,
      zone: zone,
      speedKmh: speed,
      telemetryFresh: fresh,
    );

void main() {
  test('lỗi bảo mật thắng mọi trạng thái khác', () {
    final v = deriveSmartKey(_in(fault: true, locked: false));
    expect(v.state, SmartKeyState.securityLock);
    expect(v.tone, SmartKeyTone.red);
  });

  test('chưa cấp quyền / Bluetooth tắt → DISCONNECTED (xám)', () {
    expect(deriveSmartKey(_in(perm: false)).state, SmartKeyState.disconnected);
    final v = deriveSmartKey(_in(bt: false));
    expect(v.state, SmartKeyState.disconnected);
    expect(v.tone, SmartKeyTone.grey);
  });

  test('chưa kết nối lần nào → SEARCHING (vàng)', () {
    final v = deriveSmartKey(_in(connected: false, ever: false));
    expect(v.state, SmartKeyState.searching);
    expect(v.tone, SmartKeyTone.yellow);
  });

  test('đang kết nối lại → SEARCHING, không phải DISCONNECTED', () {
    expect(deriveSmartKey(_in(connected: false, connecting: true)).state,
        SmartKeyState.searching);
  });

  test('đã kết nối BLE nhưng chưa xác thực → AUTHENTICATING, không NEARBY', () {
    final v = deriveSmartKey(_in(auth: false, zone: ProximityZone.near));
    expect(v.state, SmartKeyState.authenticating);
  });

  test('đã xác thực + gần + xe khóa → NEARBY (xanh)', () {
    final v = deriveSmartKey(_in());
    expect(v.state, SmartKeyState.nearby);
    expect(v.tone, SmartKeyTone.green);
  });

  test('đã xác thực + xa/chưa rõ khoảng cách + xe khóa → LOCKED (đỏ)', () {
    expect(deriveSmartKey(_in(zone: ProximityZone.far)).state,
        SmartKeyState.locked);
    expect(deriveSmartKey(_in(zone: ProximityZone.unknown)).state,
        SmartKeyState.locked);
  });

  test('xe đã mở khóa + đã xác thực → UNLOCKED', () {
    expect(deriveSmartKey(_in(locked: false)).state, SmartKeyState.unlocked);
  });

  test('mất BLE khi xe đang chạy → chỉ cảnh báo, có warning', () {
    final v = deriveSmartKey(
        _in(connected: false, ever: true, on: true, speed: 20));
    expect(v.state, SmartKeyState.disconnected);
    expect(v.warning, isNotNull);
    expect(v.warning, contains('KHÔNG'));
  });

  test('mất BLE, xe bật, chưa biết tốc độ → vẫn coi là có thể đang chạy', () {
    final v = deriveSmartKey(_in(
        connected: false, ever: true, on: true, speed: null, fresh: false));
    expect(v.warning, isNotNull);
  });

  test('mất BLE khi xe tắt và đứng yên → không cảnh báo chạy', () {
    final v = deriveSmartKey(
        _in(connected: false, ever: true, on: false, speed: 0));
    expect(v.state, SmartKeyState.disconnected);
    expect(v.warning, isNull);
  });
}
