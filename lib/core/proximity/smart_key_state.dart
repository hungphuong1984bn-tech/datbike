// Máy trạng thái Smart Key — THUẦN DART, chỉ SUY RA trạng thái hiển thị từ dữ
// liệu có sẵn. KHÔNG gửi lệnh, KHÔNG thay thế ProximityEngine / BleController.
//
// RSSI/khoảng cách KHÔNG phải bằng chứng xác thực: trạng thái NEARBY/UNLOCKED
// chỉ xuất hiện khi phiên đã được xe xác thực (authorized = true).
// Mất BLE khi xe đang chạy → chỉ DISCONNECTED + cảnh báo, không khóa.

import 'package:flutter/foundation.dart';

import 'proximity_engine.dart';

enum SmartKeyState {
  locked, // Xe đã khóa
  searching, // Đang tìm thiết bị
  authenticating, // Đang xác thực
  nearby, // Đã nhận diện thiết bị trong phạm vi (đã xác thực)
  unlocked, // Đã mở khóa hợp lệ
  disconnected, // Mất kết nối
  securityLock, // Khóa bảo mật
}

/// Màu ngữ nghĩa: xanh = đã xác thực, vàng = đang tìm, đỏ = khóa/lỗi bảo mật,
/// xám = mất kết nối.
enum SmartKeyTone { green, yellow, red, grey }

@immutable
class SmartKeyInput {
  final bool bluetoothOn;
  final bool permissionGranted;
  final bool connected;
  final bool connecting; // đang quét / kết nối / kết nối lại
  final bool everConnected; // đã từng có phiên trong lần chạy này
  final bool authorized;
  final bool securityFault; // sai xác thực lặp lại, thiết bị lạ, nghi phát lại…
  final bool bikeLocked;
  final bool bikeOn;
  final ProximityZone zone;
  final double? speedKmh;
  final bool telemetryFresh;

  const SmartKeyInput({
    required this.bluetoothOn,
    required this.permissionGranted,
    required this.connected,
    required this.connecting,
    required this.everConnected,
    required this.authorized,
    required this.securityFault,
    required this.bikeLocked,
    required this.bikeOn,
    required this.zone,
    required this.speedKmh,
    required this.telemetryFresh,
  });
}

@immutable
class SmartKeyView {
  final SmartKeyState state;
  final SmartKeyTone tone;
  final String title;
  final String detail;

  /// Có cảnh báo an toàn cần hiện nổi bật (ví dụ mất BLE khi xe đang chạy).
  final String? warning;

  const SmartKeyView(this.state, this.tone, this.title, this.detail,
      {this.warning});
}

/// Xe có thể đang chạy? "Chưa biết tốc độ" KHÔNG được coi là đứng yên.
bool smartKeyMaybeMoving(SmartKeyInput i) =>
    i.speedKmh == null || !i.telemetryFresh || i.speedKmh! > 0.5;

SmartKeyView deriveSmartKey(SmartKeyInput i) {
  if (i.securityFault) {
    return const SmartKeyView(
      SmartKeyState.securityLock,
      SmartKeyTone.red,
      'Khóa bảo mật',
      'Phát hiện xác thực bất thường. Smart Key bị vô hiệu cho tới khi bạn '
          'ghép đôi/xác thực lại.',
    );
  }
  if (!i.permissionGranted || !i.bluetoothOn) {
    return SmartKeyView(
      SmartKeyState.disconnected,
      SmartKeyTone.grey,
      'Mất kết nối',
      !i.permissionGranted
          ? 'Chưa cấp quyền Bluetooth — Smart Key không hoạt động.'
          : 'Bluetooth đang tắt — Smart Key không hoạt động.',
      warning: _driveWarning(i),
    );
  }
  if (!i.connected) {
    if (i.connecting || !i.everConnected) {
      return const SmartKeyView(
        SmartKeyState.searching,
        SmartKeyTone.yellow,
        'Đang tìm xe',
        'Đang tìm và kết nối tới xe đã ghép đôi.',
      );
    }
    return SmartKeyView(
      SmartKeyState.disconnected,
      SmartKeyTone.grey,
      'Mất kết nối',
      'Mất liên lạc với xe. Mất tín hiệu không đồng nghĩa với rời xe.',
      warning: _driveWarning(i),
    );
  }
  if (!i.authorized) {
    return const SmartKeyView(
      SmartKeyState.authenticating,
      SmartKeyTone.yellow,
      'Đang xác thực',
      'Đã kết nối BLE nhưng chưa xác thực phiên — chưa có quyền điều khiển.',
    );
  }
  // Từ đây: đã kết nối + đã xác thực.
  if (!i.bikeLocked) {
    return const SmartKeyView(
      SmartKeyState.unlocked,
      SmartKeyTone.green,
      'Đã mở khóa',
      'Xe đã mở khóa. Đến gần chỉ đánh thức/xác thực, không tự cho xe chạy.',
    );
  }
  if (i.zone == ProximityZone.near) {
    return const SmartKeyView(
      SmartKeyState.nearby,
      SmartKeyTone.green,
      'Đã nhận diện',
      'Thiết bị đã xác thực đang trong phạm vi.',
    );
  }
  return const SmartKeyView(
    SmartKeyState.locked,
    SmartKeyTone.red,
    'Đã khóa',
    'Xe đang khóa. Thiết bị nằm ngoài phạm vi hoặc chưa xác định khoảng cách.',
  );
}

String? _driveWarning(SmartKeyInput i) {
  if (!i.everConnected) return null;
  if (smartKeyMaybeMoving(i) && i.bikeOn) {
    return 'Mất BLE khi xe có thể đang chạy — ứng dụng chỉ cảnh báo, KHÔNG '
        'khóa hay ngắt nguồn. Dừng xe an toàn rồi kết nối lại.';
  }
  return null;
}
