// Tìm trạm sạc quanh vị trí từ OpenStreetMap (Overpass API, amenity=charging_station).
//
// GIỚI HẠN (hiển thị cho người dùng):
//  • Cần Internet. Offline chỉ dùng được kết quả đã lưu lần tìm gần nhất.
//  • Dữ liệu do cộng đồng OSM nhập, có thể thiếu/sai.
//  • App KHÔNG xác minh trạm có tương thích bộ sạc/cổng sạc của Datbike hay không.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChargingStation {
  final String id;
  final String name;
  final String? operator;
  final double lat;
  final double lng;

  /// Mô tả ổ cắm/đầu sạc lấy từ thẻ OSM (có thể rỗng).
  final String? sockets;
  final String? capacity;

  const ChargingStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.operator,
    this.sockets,
    this.capacity,
  });

  LatLng get position => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        if (operator != null) 'operator': operator,
        if (sockets != null) 'sockets': sockets,
        if (capacity != null) 'capacity': capacity,
      };

  factory ChargingStation.fromJson(Map<String, dynamic> j) => ChargingStation(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? 'Trạm sạc',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        operator: j['operator'] as String?,
        sockets: j['sockets'] as String?,
        capacity: j['capacity'] as String?,
      );
}

class StationResult {
  final List<ChargingStation> stations;
  final bool fromCache;
  final DateTime? cachedAt;
  final String? error;
  const StationResult(this.stations, {this.fromCache = false, this.cachedAt, this.error});
}

class ChargingStationService {
  ChargingStationService._();

  static const String _endpoint = 'https://overpass-api.de/api/interpreter';
  static const String _cacheKey = 'charge_stations_cache_v1';

  static String buildQuery(double lat, double lng, int radiusM) =>
      '[out:json][timeout:20];'
      '(node["amenity"="charging_station"](around:$radiusM,$lat,$lng);'
      'way["amenity"="charging_station"](around:$radiusM,$lat,$lng););'
      'out center 80;';

  /// Phân tích JSON của Overpass. Bỏ qua phần tử thiếu tọa độ. Hàm thuần.
  static List<ChargingStation> parse(String body) {
    final data = jsonDecode(body);
    if (data is! Map || data['elements'] is! List) return const [];
    final out = <ChargingStation>[];
    for (final e in data['elements'] as List) {
      if (e is! Map) continue;
      final center = e['center'];
      final lat = (e['lat'] ?? (center is Map ? center['lat'] : null)) as num?;
      final lon = (e['lon'] ?? (center is Map ? center['lon'] : null)) as num?;
      if (lat == null || lon == null) continue;
      final tags = (e['tags'] is Map) ? Map<String, dynamic>.from(e['tags'] as Map) : <String, dynamic>{};
      final sockets = <String>[];
      tags.forEach((k, v) {
        if (k.startsWith('socket:') && k.split(':').length == 2) sockets.add('${k.substring(7)}×$v');
      });
      final op = tags['operator'] as String? ?? tags['brand'] as String?;
      out.add(ChargingStation(
        id: '${e['type']}/${e['id']}',
        name: (tags['name'] as String?) ?? op ?? 'Trạm sạc',
        operator: op,
        lat: lat.toDouble(),
        lng: lon.toDouble(),
        sockets: sockets.isEmpty ? null : sockets.join(', '),
        capacity: tags['capacity'] as String?,
      ));
    }
    return out;
  }

  static Future<StationResult> fetchNear(double lat, double lng, {int radiusM = 8000}) async {
    String? error;
    try {
      final res = await http
          .post(Uri.parse(_endpoint), body: {'data': buildQuery(lat, lng, radiusM)})
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final list = parse(utf8.decode(res.bodyBytes));
        await _saveCache(lat, lng, list);
        return StationResult(list);
      }
      error = 'Máy chủ dữ liệu trạm sạc trả lỗi ${res.statusCode}';
    } catch (e) {
      error = 'Không tải được dữ liệu trạm sạc: $e';
    }
    final cached = await _loadCache(lat, lng);
    if (cached != null) {
      return StationResult(cached.$1, fromCache: true, cachedAt: cached.$2, error: error);
    }
    return StationResult(const [], error: error);
  }

  static Future<void> _saveCache(double lat, double lng, List<ChargingStation> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'lat': lat,
          'lng': lng,
          'at': DateTime.now().toIso8601String(),
          'stations': list.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  /// Chỉ dùng cache nếu lần tìm trước nằm trong ~15 km quanh vị trí hiện tại.
  static Future<(List<ChargingStation>, DateTime)?> _loadCache(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final d = const Distance().as(
        LengthUnit.Kilometer,
        LatLng(lat, lng),
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );
      if (d > 15) return null;
      final list = (j['stations'] as List)
          .map((e) => ChargingStation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return (list, DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }
}
