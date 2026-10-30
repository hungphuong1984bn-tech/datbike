// Chính sách quyền BLE theo phiên bản Android — module THUẦN Dart để test.
//
//   Android 12+ (API 31+): cần BLUETOOTH_SCAN + BLUETOOTH_CONNECT.
//       Manifest khai BLUETOOTH_SCAN với neverForLocation nên KHÔNG cần quyền
//       Vị trí để quét BLE.
//   Android 11 trở xuống (API ≤ 30): cần ACCESS_FINE_LOCATION (hoặc
//       COARSE) VÀ dịch vụ Vị trí của hệ thống phải bật, nếu không scan trả
//       về 0 kết quả mà không báo lỗi. Không có quyền BLUETOOTH_CONNECT
//       runtime ở các bản này (quyền Bluetooth cũ là quyền "install-time").

enum PermState { granted, denied, permanentlyDenied }

enum BlePermissionResult {
  granted,
  denied,
  permanentlyDenied,
  locationServiceOff,
}

/// Quyết định kết quả cuối cùng từ trạng thái từng quyền.
/// [sdkInt] là Build.VERSION.SDK_INT của Android.
BlePermissionResult decideBlePermission({
  required int sdkInt,
  required PermState scan,
  required PermState connect,
  required PermState location,
  required bool locationServiceEnabled,
}) {
  if (sdkInt >= 31) {
    final needed = [scan, connect];
    if (needed.every((s) => s == PermState.granted)) {
      return BlePermissionResult.granted;
    }
    if (needed.any((s) => s == PermState.permanentlyDenied)) {
      return BlePermissionResult.permanentlyDenied;
    }
    return BlePermissionResult.denied;
  }
  // Android ≤ 11: chỉ quyền Vị trí + dịch vụ Vị trí quyết định.
  if (location == PermState.granted) {
    return locationServiceEnabled
        ? BlePermissionResult.granted
        : BlePermissionResult.locationServiceOff;
  }
  return location == PermState.permanentlyDenied
      ? BlePermissionResult.permanentlyDenied
      : BlePermissionResult.denied;
}
