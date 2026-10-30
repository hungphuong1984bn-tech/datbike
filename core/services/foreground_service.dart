import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Quản lý Foreground Service gốc trên Android để giữ kết nối BLE sống
/// liên tục trong nền (ngay cả khi vuốt đóng app hay tắt màn hình).
class ForegroundService {
  static const _channel = MethodChannel('vn.datbike/export');

  /// Bật Foreground Service với thông báo thường trực
  static Future<void> start({String? title, String? text}) async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
      final args = <String, dynamic>{};
      if (title != null) args['title'] = title;
      if (text != null) args['text'] = text;
      await _channel.invokeMethod('startForegroundService', args);
    } catch (_) {}
  }

  /// Tắt Foreground Service khi người dùng chủ động ngắt kết nối
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }
}
