// Mở ứng dụng bản đồ bên ngoài để dẫn đường tới trạm. Dùng kênh native sẵn có
// "vn.datbike/export" → "openMap" (ACTION_VIEW). Không tự dẫn đường trong app.

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class ExternalNav {
  ExternalNav._();

  static const _channel = MethodChannel('vn.datbike/export');

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
}
