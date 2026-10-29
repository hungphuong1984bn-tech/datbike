// Xin quyền runtime cho BLE — flutter_blue_plus KHÔNG tự xin.
//
// Android 12+ (API 31+): BLUETOOTH_SCAN + BLUETOOTH_CONNECT.
// Android ≤ 11 (API ≤ 30): ACCESS_FINE_LOCATION + dịch vụ Vị trí bật.
// Không xin quyền → scan trả về 0 kết quả MÀ KHÔNG BÁO LỖI (bug "không tìm
// thấy xe" dù Settings thấy). Logic quyết định nằm ở ble_permission_policy.dart
// (thuần Dart, có test); file này chỉ nối với permission_handler/device_info.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_logger.dart';
import 'ble_permission_policy.dart';

export 'ble_permission_policy.dart' show BlePermissionResult;

class BlePermissions {
  BlePermissions._();

  static int? _sdkIntCache;

  static Future<int> _sdkInt() async {
    final cached = _sdkIntCache;
    if (cached != null) return cached;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _sdkIntCache = info.version.sdkInt;
    } catch (e) {
      // Không đọc được SDK → coi như Android mới (API 31+), cách an toàn
      // vì buộc xin đúng quyền Bluetooth thay vì quyền Vị trí.
      BleLogger.instance.event('perm_sdk_unknown', {'error': '$e'});
      return 31;
    }
  }

  static PermState _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermState.granted;
    if (s.isPermanentlyDenied) return PermState.permanentlyDenied;
    return PermState.denied;
  }

  /// Kiểm tra (và xin nếu cần) quyền, trả về kết quả CÓ PHÂN LOẠI.
  static Future<BlePermissionResult> check() async {
    if (kIsWeb) return BlePermissionResult.granted;
    if (!Platform.isAndroid) return BlePermissionResult.granted;

    final sdk = await _sdkInt();
    final PermState scan, connect, location;
    var locationServiceEnabled = true;

    if (sdk >= 31) {
      final r = await [Permission.bluetoothScan, Permission.bluetoothConnect]
          .request();
      scan = _map(r[Permission.bluetoothScan] ?? PermissionStatus.denied);
      connect = _map(r[Permission.bluetoothConnect] ?? PermissionStatus.denied);
      location = PermState.granted; // không bắt buộc cho BLE trên API 31+
    } else {
      final st = await Permission.locationWhenInUse.request();
      location = _map(st);
      scan = PermState.granted; // quyền Bluetooth cũ là install-time
      connect = PermState.granted;
      if (location == PermState.granted) {
        try {
          locationServiceEnabled =
              await Permission.locationWhenInUse.serviceStatus.isEnabled;
        } catch (_) {
          locationServiceEnabled = true;
        }
      }
    }

    final result = decideBlePermission(
      sdkInt: sdk,
      scan: scan,
      connect: connect,
      location: location,
      locationServiceEnabled: locationServiceEnabled,
    );
    BleLogger.instance.event('perm_check', {
      'sdk': sdk,
      'scan': scan.name,
      'connect': connect.name,
      'location': location.name,
      'location_service': locationServiceEnabled,
      'result': result.name,
    });
    return result;
  }

  /// Xin đủ quyền BLE. Trả về true nếu scan/connect được phép chạy.
  static Future<bool> ensure() async =>
      (await check()) == BlePermissionResult.granted;

  /// Quyền bị từ chối vĩnh viễn? → cần mở Settings.
  static Future<bool> permanentlyDenied() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    final sdk = await _sdkInt();
    if (sdk >= 31) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      return scan.isPermanentlyDenied || connect.isPermanentlyDenied;
    }
    final location = await Permission.locationWhenInUse.status;
    return location.isPermanentlyDenied;
  }
}
