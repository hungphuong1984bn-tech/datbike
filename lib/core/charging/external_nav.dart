// Mở ứng dụng bản đồ bên ngoài để dẫn đường tới trạm. Dùng kênh native sẵn có
// "vn.datbike/export" → "openMap" (ACTION_VIEW). Không tự dẫn đường trong app.

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class ExternalNav {
  ExternalNav._();

  static const _channel = MethodChannel('vn.datbike/export');

  /// Chuẩn hóa số điện thoại cho `tel:`; null nếu không có chữ số hợp lệ. Hàm thuần.
  static String? telUri(String? raw) {
    if (raw == null) return null;
    final first = raw.split(RegExp(r'[;/,]')).first;
    final cleaned = first.replaceAll(RegExp(r'[^0-9+]'), '');
    final digits = cleaned.replaceAll('+', '');
    if (digits.length < 6) return null;
    return 'tel:$cleaned';
  }

  /// Mở trình quay số với số đã điền sẵn (người dùng tự bấm gọi). false nếu không mở được.
  static Future<bool> dial(String? phone) async {
    final u = telUri(phone);
    if (u == null) return false;
    try {
      return (await _channel.invokeMethod<bool>('openMap', {'url': u})) == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Thử Google Maps (nếu có cài) → nếu không có ứng dụng nhận thì mở bằng
  /// bất kỳ ứng dụng bản đồ nào xử lý `geo:`. Trả về false nếu cả hai đều thất bại.
  static Future<bool> navigateTo(LatLng p, String label) async {
    final safe = Uri.encodeComponent(label);
    final urls = <String>[
      'google.navigation:q=${p.latitude},${p.longitude}&mode=l',
      'geo:${p.latitude},${p.longitude}?q=${p.latitude},${p.longitude}($safe)',
    ];
    for (final u in urls) {
      try {
        final ok = await _channel.invokeMethod<bool>('openMap', {'url': u});
        if (ok == true) return true;
      } on PlatformException {
        continue;
      } on MissingPluginException {
        return false;
      }
    }
    return false;
  }

  /// Mở một liên kết (vd. tìm kiếm Google Maps theo địa chỉ) bằng ứng dụng nhận ACTION_VIEW. false nếu không mở được.
  static Future<bool> openUrl(String url) async {
    try {
      return (await _channel.invokeMethod<bool>('openMap', {'url': url})) == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
