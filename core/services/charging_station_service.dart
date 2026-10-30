// Tìm trạm sạc quanh vị trí từ OpenStreetMap (Overpass API, amenity=charging_station).
//
// GIỚI HẠN (hiển thị cho người dùng):
//  • Cần Internet. Offline chỉ dùng được kết quả đã lưu lần tìm gần nhất.
//  • Dữ liệu do cộng đồng OSM nhập, có thể thiếu/sai.
//  • App KHÔNG xác minh trạm có tương thích bộ sạc/cổng sạc của xe hay không.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loại phương tiện trạm hỗ trợ — CHỈ lấy từ thẻ dữ liệu nguồn, không suy đoán từ tên.
enum VehicleSupport { motorbike, car, both, unknown }

/// Trạng thái hoạt động. OSM không có dữ liệu trực tiếp nên mặc định là
/// [unverified]; [active] chỉ dùng được khi một nguồn khác xác nhận.
enum StationStatus { active, paused, closed, unverified }

class ChargingStation {
  final String id;
  final String name;
  final String? operator;
  final double lat;
  final double lng;

  /// Mô tả ổ cắm/đầu sạc lấy từ thẻ OSM (có thể rỗng).
  final String? sockets;
  final String? capacity;

  // ── Trường mở rộng: null = nguồn KHÔNG cung cấp (UI hiển thị "Chưa có dữ liệu"). ──
  final VehicleSupport vehicle;
  final StationStatus status;
  final double? powerKw;
  final String? address;
  final String? openingHours;
  final String? fee;
  final String? phone;
  final String? website;

  /// Tên nguồn dữ liệu (vd. "OpenStreetMap").
  final String source;

  /// Thời điểm bản ghi được chỉnh sửa gần nhất ở nguồn (KHÔNG phải thời điểm xác minh).
  final DateTime? updatedAt;

  const ChargingStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.operator,
    this.sockets,
    this.capacity,
    this.vehicle = VehicleSupport.unknown,
    this.status = StationStatus.unverified,
    this.powerKw,
    this.address,
    this.openingHours,
    this.fee,
    this.phone,
    this.website,
    this.source = 'OpenStreetMap',
    this.updatedAt,
  });

  LatLng get position => LatLng(lat, lng);

  /// Số cổng sạc, chỉ khi thẻ `capacity` là số nguyên hợp lệ.
  int? get ports => int.tryParse((capacity ?? '').trim());

  bool get supportsMotorbike => vehicle == VehicleSupport.motorbike || vehicle == VehicleSupport.both;
  bool get carOnly => vehicle == VehicleSupport.car;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        if (operator != null) 'operator': operator,
        if (sockets != null) 'sockets': sockets,
        if (capacity != null) 'capacity': capacity,
        'vehicle': vehicle.name,
        'status': status.name,
        if (powerKw != null) 'powerKw': powerKw,
        if (address != null) 'address': address,
        if (openingHours != null) 'openingHours': openingHours,
        if (fee != null) 'fee': fee,
        if (phone != null) 'phone': phone,
        if (website != null) 'website': website,
        'source': source,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  factory ChargingStation.fromJson(Map<String, dynamic> j) => ChargingStation(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? 'Trạm sạc',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        operator: j['operator'] as String?,
        sockets: j['sockets'] as String?,
        capacity: j['capacity'] as String?,
        vehicle: _enum(VehicleSupport.values, j['vehicle'], VehicleSupport.unknown),
        status: _enum(StationStatus.values, j['status'], StationStatus.unverified),
        powerKw: (j['powerKw'] as num?)?.toDouble(),
        address: j['address'] as String?,
        openingHours: j['openingHours'] as String?,
        fee: j['fee'] as String?,
        phone: j['phone'] as String?,
        website: j['website'] as String?,
        source: (j['source'] as String?) ?? 'OpenStreetMap',
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
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
  static const String _cacheKey = 'charge_stations_cache_v2';

  static String buildQuery(double lat, double lng, int radiusM) =>
      '[out:json][timeout:20];'
      '(node["amenity"="charging_station"](around:$radiusM,$lat,$lng);'
      'way["amenity"="charging_station"](around:$radiusM,$lat,$lng););'
      'out center meta 150;';

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
        vehicle: _vehicleFromTags(tags),
        status: _statusFromTags(tags),
        powerKw: _maxKw(tags),
        address: _address(tags),
        openingHours: _str(tags['opening_hours']),
        fee: _fee(tags),
        phone: _str(tags['contact:phone'] ?? tags['phone']),
        website: _str(tags['contact:website'] ?? tags['website']),
        updatedAt: DateTime.tryParse('${e['timestamp'] ?? ''}'),
      ));
    }
    return out;
  }


  static String? _str(Object? v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Loại xe: chỉ theo thẻ `motorcycle` / `motorcar`. Không có thẻ → unknown.
  static VehicleSupport _vehicleFromTags(Map<String, dynamic> t) {
    final moto = '${t['motorcycle'] ?? t['scooter'] ?? ''}' == 'yes';
    final car = '${t['motorcar'] ?? ''}' == 'yes';
    final motoNo = '${t['motorcycle'] ?? ''}' == 'no';
    if (moto && car) return VehicleSupport.both;
    if (moto) return VehicleSupport.motorbike;
    if (car && (motoNo || t['motorcycle'] == null)) return VehicleSupport.car;
    return VehicleSupport.unknown;
  }

  /// Trạng thái: chỉ kết luận "đã đóng/tạm ngừng" khi thẻ nói rõ; còn lại chưa xác minh.
  static StationStatus _statusFromTags(Map<String, dynamic> t) {
    final oh = '${t['opening_hours'] ?? ''}'.trim().toLowerCase();
    if (oh == 'off' || oh == 'closed') return StationStatus.closed;
    if ('${t['disused'] ?? ''}' == 'yes' || '${t['abandoned'] ?? ''}' == 'yes') {
      return StationStatus.closed;
    }
    final op = '${t['operational_status'] ?? t['construction'] ?? ''}'.toLowerCase();
    if (op == 'broken' || op == 'maintenance' || op == 'closed_temporarily') {
      return StationStatus.paused;
    }
    return StationStatus.unverified;
  }

  /// Công suất lớn nhất từ các thẻ `socket:*:output` / `charging_station:output`.
  static double? _maxKw(Map<String, dynamic> t) {
    double? best;
    t.forEach((k, v) {
      if (k.endsWith(':output') || k == 'charging_station:output') {
        final m = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch('$v');
        if (m != null) {
          final x = double.tryParse(m.group(1)!.replaceAll(',', '.'));
          if (x != null && x > 0 && (best == null || x > best!)) best = x;
        }
      }
    });
    return best;
  }

  static String? _address(Map<String, dynamic> t) {
    final full = _str(t['addr:full']);
    if (full != null) return full;
    final parts = <String>[
      [t['addr:housenumber'], t['addr:street']].where((e) => _str(e) != null).join(' '),
      if (_str(t['addr:suburb']) != null) '${t['addr:suburb']}',
      if (_str(t['addr:district']) != null) '${t['addr:district']}',
      if (_str(t['addr:city']) != null) '${t['addr:city']}',
      if (_str(t['addr:province']) != null) '${t['addr:province']}',
    ].where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String? _fee(Map<String, dynamic> t) {
    final charge = _str(t['charge']);
    final fee = _str(t['fee']);
    if (charge != null) return charge;
    if (fee == 'no') return 'Miễn phí (theo dữ liệu nguồn)';
    if (fee == 'yes') return 'Có thu phí (chưa rõ mức giá)';
    return null;
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
