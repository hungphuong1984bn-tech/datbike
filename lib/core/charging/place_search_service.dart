// Tìm địa điểm / địa chỉ / tỉnh thành bằng Nominatim (OpenStreetMap).
//
// Điều kiện sử dụng công khai của Nominatim: tối đa 1 yêu cầu/giây, phải có
// User-Agent định danh, KHÔNG dùng cho tự động hoàn thành khi gõ. Vì vậy chỉ
// gọi khi người dùng chủ động bấm tìm. Dùng nhiều/thương mại → cần tự dựng máy
// chủ hoặc dùng nhà cung cấp trả phí.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../brand/app_info.dart' show kAppVersion;

class PlaceHit {
  final String name;
  final LatLng position;
  const PlaceHit(this.name, this.position);
}

class PlaceSearchService {
  PlaceSearchService._();

  static Uri buildUri(String q) => Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'jsonv2',
        'countrycodes': 'vn',
        'accept-language': 'vi',
        'limit': '6',
      });

  static List<PlaceHit> parse(String body) {
    final j = jsonDecode(body);
    if (j is! List) return const [];
    final out = <PlaceHit>[];
    for (final e in j) {
      if (e is! Map) continue;
      final lat = double.tryParse('${e['lat']}');
      final lon = double.tryParse('${e['lon']}');
      if (lat == null || lon == null) continue;
      out.add(PlaceHit('${e['display_name'] ?? q0(e)}', LatLng(lat, lon)));
    }
    return out;
  }

  static String q0(Map e) => '${e['name'] ?? 'Địa điểm'}';

  /// Ném Exception có thông điệp tiếng Việt khi lỗi mạng / máy chủ.
  static Future<List<PlaceHit>> search(String q) async {
    final t = q.trim();
    if (t.length < 2) return const [];
    try {
      final res = await http
          .get(buildUri(t), headers: {'User-Agent': 'THBIKE/$kAppVersion (tim-tram-sac)'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('Máy chủ tìm địa điểm trả lỗi ${res.statusCode}.');
      }
      return parse(utf8.decode(res.bodyBytes));
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Không tìm được địa điểm (kiểm tra kết nối mạng): $e');
    }
  }
}

/// Kết quả đổi tọa độ → địa chỉ (Nominatim /reverse).
class ReverseHit {
  final String address;
  final String province;
  final String district;
  const ReverseHit(this.address, this.province, this.district);
}

class PlaceReverseService {
  PlaceReverseService._();

  static Uri buildUri(double lat, double lng) => Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toStringAsFixed(6),
        'lon': lng.toStringAsFixed(6),
        'format': 'jsonv2',
        'accept-language': 'vi',
        'zoom': '18',
        'addressdetails': '1',
      });

  /// Phân tích phản hồi; null nếu không có địa chỉ. Hàm thuần.
  static ReverseHit? parse(String body) {
    final j = jsonDecode(body);
    if (j is! Map || j['error'] != null) return null;
    final name = '${j['display_name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final a = j['address'];
    String pick(List<String> keys) {
      if (a is! Map) return '';
      for (final k in keys) {
        final v = a[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    return ReverseHit(
      name,
      pick(const ['city', 'state', 'province']),
      pick(const ['city_district', 'district', 'county', 'suburb', 'town']),
    );
  }

  /// null khi không có kết quả hoặc lỗi mạng (người dùng vẫn tự nhập được địa chỉ).
  /// Điều kiện Nominatim: chỉ gọi khi người dùng chủ động (chạm giữ), không gọi liên tục.
  static Future<ReverseHit?> lookup(double lat, double lng) async {
    try {
      final res = await http
          .get(buildUri(lat, lng), headers: {'User-Agent': 'THBIKE/$kAppVersion (tim-tram-sac)'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return parse(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }
}
