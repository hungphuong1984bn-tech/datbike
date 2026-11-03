// Mở ứng dụng bên ngoài: Google Maps để dẫn đường tới trạm, trình quay số.
//
// Dẫn đường dùng liên kết Directions chính thức của Google Maps
// (https://www.google.com/maps/dir/?api=1&destination=lat,lng) — KHÔNG cần API key.
//  • Máy đã cài Google Maps → mở thẳng ứng dụng, điểm đi là vị trí hiện tại, người dùng
//    chọn phương tiện (xe máy / ô tô / đi bộ…) ngay trong Google Maps.
//  • Chưa cài → liên kết mở trên trình duyệt (Google Maps web).
//  • Không mở được cả hai → thử `geo:` (bất kỳ ứng dụng bản đồ nào).
// Android dùng kênh native "openMap" (ACTION_VIEW) như trước; iOS (chưa có kênh)
// dùng url_launcher. THBIKE chỉ bị đưa xuống nền, quay lại là còn nguyên màn hình.

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Phương tiện gợi ý cho Google Maps. [choose] = để người dùng chọn trong Google Maps.
enum NavMode {
  choose('Chọn trong Google Maps'),
  motorbike('Xe máy'),
  car('Ô tô'),
  walk('Đi bộ');

  final String label;
  const NavMode(this.label);
}

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

  /// Liên kết Directions của Google Maps tới [p]. Hàm thuần, không cần API key.
  /// Bỏ `origin` → Google Maps tự lấy vị trí hiện tại của thiết bị.
  static Uri directionsUri(LatLng p, {NavMode mode = NavMode.choose}) => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '${p.latitude},${p.longitude}',
        if (mode == NavMode.motorbike) 'travelmode': 'two-wheeler',
        if (mode == NavMode.car) 'travelmode': 'driving',
        if (mode == NavMode.walk) 'travelmode': 'walking',
      });

  /// Intent điều hướng trực tiếp của Google Maps (Android). null khi [mode] = choose.
  static String? navigationIntent(LatLng p, NavMode mode) {
    final m = switch (mode) {
      NavMode.motorbike => 'l',
      NavMode.car => 'd',
      NavMode.walk => 'w',
      NavMode.choose => null,
    };
    return m == null ? null : 'google.navigation:q=${p.latitude},${p.longitude}&mode=$m';
  }

  /// Danh sách đích thử lần lượt, từ ưu tiên cao đến dự phòng. Hàm thuần.
  static List<String> navigationTargets(LatLng p, String label, {NavMode mode = NavMode.choose}) {
    final safe = Uri.encodeComponent(label);
    return [
      ?navigationIntent(p, mode),
      directionsUri(p, mode: mode).toString(),
      'geo:${p.latitude},${p.longitude}?q=${p.latitude},${p.longitude}($safe)',
    ];
  }

  static Future<bool> _viaLauncher(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Kênh native trước (Android); chưa có kênh (iOS/khác) thì dùng url_launcher.
  static Future<bool> _open(String url) async {
    try {
      return (await _channel.invokeMethod<bool>('openMap', {'url': url})) == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return _viaLauncher(url);
    }
  }

  /// Mở trình quay số với số đã điền sẵn (người dùng tự bấm gọi). false nếu không mở được.
  static Future<bool> dial(String? phone) async {
    final u = telUri(phone);
    if (u == null) return false;
    return _open(u);
  }

  /// Dẫn đường tới [p] bằng Google Maps (xem đầu file). Trả về false nếu mọi cách đều thất bại.
  static Future<bool> navigateTo(LatLng p, String label, {NavMode mode = NavMode.choose}) async {
    for (final u in navigationTargets(p, label, mode: mode)) {
      if (await _open(u)) return true;
    }
    return false;
  }

  /// Mở một liên kết (vd. tìm kiếm Google Maps theo địa chỉ). false nếu không mở được.
  static Future<bool> openUrl(String url) => _open(url);
}
