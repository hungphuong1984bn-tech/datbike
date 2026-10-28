// Xin quyền runtime cho BLE — flutter_blue_plus KHÔNG tự xin.
// Android 12+: BLUETOOTH_SCAN + BLUETOOTH_CONNECT
// Android < 12: ACCESS_FINE_LOCATION (bắt buộc để scan có kết quả)
// Không xin quyền → scan trả về 0 kết quả MÀ KHÔNG BÁO LỖI (bug "không tìm
// thấy xe" dù Settings thấy).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class BlePermissions {
  BlePermissions._();

  /// Xin đủ quyền BLE. Trả về true nếu scan được phép chạy.
  static Future<bool> ensure() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // Android 12+ (API 31+): bluetoothScan/bluetoothConnect quyết định.
    // Android < 12: locationWhenInUse quyết định.
    final scan = results[Permission.bluetoothScan] ??
        PermissionStatus.permanentlyDenied;
    final connect = results[Permission.bluetoothConnect] ??
        PermissionStatus.permanentlyDenied;
    final location =
        results[Permission.locationWhenInUse] ?? PermissionStatus.permanentlyDenied;

    final scanOk = scan.isGranted || location.isGranted;
    return scanOk && connect.isGranted;
  }

  /// Quyền bị từ chối vĩnh viễn? → cần mở Settings.
  static Future<bool> permanentlyDenied() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    final scan = await Permission.bluetoothScan.status;
    final location = await Permission.locationWhenInUse.status;
    return scan.isPermanentlyDenied || location.isPermanentlyDenied;
  }
}
