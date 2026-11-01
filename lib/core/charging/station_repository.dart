// Kho dữ liệu trạm sạc ĐỘC LẬP với bản đồ.
//
// Nguồn (theo thứ tự):
//  1. Dữ liệu Dat Bike đóng gói trong app (assets/data/datbike_stations.json) — luôn có, không cần mạng.
//  2. OpenStreetMap qua Overpass: nhiều máy chủ, thử lần lượt, retry có giới hạn.
//  3. Cache cục bộ nhiều vùng — dùng khi mọi máy chủ lỗi hoặc mất mạng.
//  4. Điểm do người dùng đề xuất (lưu cục bộ, luôn "chờ xác minh") — xem station_proposal_store.dart.
//
// Một nguồn lỗi KHÔNG làm mất các nguồn còn lại. Không tạo trạm/tọa độ nào trong mã.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/charging_station_service.dart';
import 'station_proposal_store.dart';

/// Gộp trùng lặp: cùng id, hoặc rất gần nhau (< [maxMeters]) và tên tương đồng / một bên tên chung.
class StationDedupe {
  StationDedupe._();

  static const double maxMeters = 40;
  static const Distance _d = Distance();

  static int _rank(ChargingStation s) => switch (s.category) {
        StationCategory.datBike => 0,
        StationCategory.partner => 1,
        StationCategory.community => 2,
      };

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _generic(String n) => n.isEmpty || n == 'trạm sạc' || n == 'tram sac';

  static bool _sameName(String a, String b) {
    final x = _norm(a), y = _norm(b);
    if (_generic(x) || _generic(y)) return true;
    if (x == y || x.contains(y) || y.contains(x)) return true;
    final tx = x.split(' ').toSet(), ty = y.split(' ').toSet();
    final inter = tx.intersection(ty).length;
    final minLen = tx.length < ty.length ? tx.length : ty.length;
    return minLen > 0 && inter / minLen >= 0.6;
  }

  static bool isDuplicate(ChargingStation a, ChargingStation b) {
    if (a.id == b.id) return true;
    final m = _d.as(LengthUnit.Meter, a.position, b.position);
    return m <= maxMeters && _sameName(a.name, b.name);
  }

  /// Bản ghi ưu tiên cao hơn (Dat Bike > đối tác > cộng đồng) được giữ; trường thiếu được bổ sung
  /// từ bản ghi trùng. Không bao giờ nâng loại hoặc trạng thái từ dữ liệu cấp thấp.
  static ChargingStation _merge(ChargingStation keep, ChargingStation other) => ChargingStation(
        id: keep.id,
        name: keep.name,
        lat: keep.lat,
        lng: keep.lng,
        operator: keep.operator ?? other.operator,
        sockets: keep.sockets ?? other.sockets,
        capacity: keep.capacity ?? other.capacity,
        vehicle: keep.vehicle != VehicleSupport.unknown ? keep.vehicle : other.vehicle,
        status: keep.status,
        powerKw: keep.powerKw ?? other.powerKw,
        address: keep.address ?? other.address,
        openingHours: keep.openingHours ?? other.openingHours,
        fee: keep.fee ?? other.fee,
        phone: keep.phone ?? other.phone,
        website: keep.website ?? other.website,
        source: keep.source,
        category: keep.category,
        chargingConfirmed: keep.chargingConfirmed,
        updatedAt: keep.updatedAt ?? other.updatedAt,
      );

  static List<ChargingStation> dedupe(Iterable<ChargingStation> input) {
    final sorted = input.toList()..sort((a, b) => _rank(a).compareTo(_rank(b)));
    final out = <ChargingStation>[];
    for (final s in sorted) {
      final i = out.indexWhere((e) => isDuplicate(e, s));
      if (i >= 0) {
        out[i] = _merge(out[i], s);
      } else {
        out.add(s);
      }
    }
    return out;
  }
}

/// Phân loại lỗi HTTP / mạng thành thông báo tiếng Việt.
class StationErrors {
  StationErrors._();

  static StationFetchError fromStatus(int code) {
    if (code == 404) return StationFetchError.notFound;
    if (code == 429) return StationFetchError.rateLimited;
    if (code >= 500) return StationFetchError.serverError;
    return StationFetchError.unknown;
  }

  static StationFetchError fromException(Object e) {
    if (e is TimeoutException) return StationFetchError.timeout;
    if (e is SocketException || e is http.ClientException) return StationFetchError.noInternet;
    if (e is FormatException) return StationFetchError.badData;
    return StationFetchError.unknown;
  }

  static String message(StationFetchError k, {int? status}) => switch (k) {
        StationFetchError.none => '',
        StationFetchError.notFound => 'Không tìm thấy dịch vụ dữ liệu trạm sạc (404).',
        StationFetchError.rateLimited => 'Máy chủ dữ liệu đang quá tải (429). Thử tải lại sau ít phút.',
        StationFetchError.serverError => 'Máy chủ dữ liệu trạm sạc đang lỗi${status == null ? '' : ' ($status)'}.',
        StationFetchError.timeout => 'Máy chủ dữ liệu không phản hồi kịp (quá thời gian chờ).',
        StationFetchError.noInternet => 'Không kết nối được Internet hoặc không phân giải được máy chủ.',
        StationFetchError.badData => 'Dữ liệu máy chủ trả về không đọc được.',
        StationFetchError.unknown => 'Không tải được dữ liệu trạm sạc.',
      };

  /// Lỗi tạm thời → đáng thử lại / thử máy chủ khác.
  static bool retryable(StationFetchError k) =>
      k == StationFetchError.rateLimited ||
      k == StationFetchError.serverError ||
      k == StationFetchError.timeout ||
      k == StationFetchError.noInternet ||
      k == StationFetchError.notFound;
}

class StationRepository {
  StationRepository._();

  /// Máy chủ Overpass (OSM) dùng lần lượt. Danh sách cấu hình được; chưa kiểm tra từ môi trường build.
  static List<String> overpassEndpoints = const [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static const Duration perRequestTimeout = Duration(seconds: 12);
  static const int maxAttempts = 4;
  static const Duration retryDelay = Duration(milliseconds: 1500);
  static const String userAgent = 'THBIKE/6 (Android; ứng dụng xe điện Dat Bike)';

  static const String seedAsset = 'assets/data/datbike_stations.json';
  static const String _cacheKey = 'charge_regions_cache_v3';
  static const String _legacyKey = 'charge_stations_cache_v2';
  static const int maxRegions = 8;

  // ── Dữ liệu đóng gói ──

  /// Phân tích file dữ liệu đóng gói. Bỏ bản ghi thiếu tọa độ hợp lệ. Hàm thuần.
  static List<ChargingStation> parseSeed(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['stations'] is! List) return const [];
      final out = <ChargingStation>[];
      for (final e in j['stations'] as List) {
        if (e is! Map) continue;
        final lat = e['lat'], lng = e['lng'];
        if (lat is! num || lng is! num) continue;
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
        out.add(ChargingStation.fromJson(Map<String, dynamic>.from(e)));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ChargingStation>> loadSeed() async {
    try {
      return parseSeed(await rootBundle.loadString(seedAsset));
    } catch (_) {
      return const [];
    }
  }

  // ── Mạng (OSM) ──

  /// Thử lần lượt các máy chủ, tối đa [maxAttempts] lần, có độ trễ giữa các lượt.
  /// Trả (danh sách, null) khi thành công hoặc (null, loại lỗi cuối).
  static Future<({List<ChargingStation>? list, StationFetchError error, int? status})> fetchOsm(
    double lat,
    double lng,
    int radiusM, {
    http.Client? client,
    List<String>? endpoints,
    Duration? timeout,
    Duration? delay,
  }) async {
    final c = client ?? http.Client();
    final eps = endpoints ?? overpassEndpoints;
    var last = StationFetchError.unknown;
    int? lastStatus;
    var attempts = 0;
    try {
      while (attempts < maxAttempts) {
        final ep = eps[attempts % eps.length];
        attempts++;
        try {
          final res = await c
              .post(
                Uri.parse(ep),
                headers: {'User-Agent': userAgent},
                body: {'data': ChargingStationService.buildQuery(lat, lng, radiusM)},
              )
              .timeout(timeout ?? perRequestTimeout);
          if (res.statusCode == 200) {
            final list = ChargingStationService.parse(utf8.decode(res.bodyBytes));
            return (list: list, error: StationFetchError.none, status: 200);
          }
          lastStatus = res.statusCode;
          last = StationErrors.fromStatus(res.statusCode);
        } catch (e) {
          last = StationErrors.fromException(e);
          lastStatus = null;
        }
        if (!StationErrors.retryable(last)) break;
        if (attempts < maxAttempts) await Future<void>.delayed(delay ?? retryDelay);
      }
    } finally {
      if (client == null) c.close();
    }
    return (list: null, error: last, status: lastStatus);
  }

  // ── Cache nhiều vùng ──

  static Future<void> saveRegion(double lat, double lng, List<ChargingStation> list, {DateTime? at}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regions = await _readRegions(prefs);
      regions.removeWhere((r) => const Distance().as(
            LengthUnit.Kilometer,
            LatLng(lat, lng),
            LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
          ) < 3);
      regions.insert(0, {
        'lat': lat,
        'lng': lng,
        'at': (at ?? DateTime.now()).toIso8601String(),
        'stations': [for (final s in list) s.toJson()],
      });
      await prefs.setString(_cacheKey, jsonEncode(regions.take(maxRegions).toList()));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> _readRegions(SharedPreferences prefs) async {
    final out = <Map<String, dynamic>>[];
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final l = jsonDecode(raw);
        if (l is List) out.addAll([for (final e in l) if (e is Map) Map<String, dynamic>.from(e)]);
      }
      // Chuyển cache cũ (v2, một vùng) sang vùng đầu tiên — không xóa dữ liệu người dùng.
      final legacy = prefs.getString(_legacyKey);
      if (legacy != null) {
        final j = jsonDecode(legacy);
        if (j is Map && j['stations'] is List && j['lat'] is num && j['lng'] is num) {
          out.add(Map<String, dynamic>.from(j));
        }
      }
    } catch (_) {}
    return out;
  }

  /// Gộp mọi vùng đã lưu (đã khử trùng lặp) + thời điểm lưu mới nhất. null nếu chưa có cache.
  static Future<({List<ChargingStation> stations, DateTime at})?> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regions = await _readRegions(prefs);
      if (regions.isEmpty) return null;
      final all = <ChargingStation>[];
      DateTime? newest;
      for (final r in regions) {
        for (final e in (r['stations'] as List? ?? const [])) {
          if (e is! Map) continue;
          try {
            all.add(ChargingStation.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
        final at = DateTime.tryParse('${r['at']}');
        if (at != null && (newest == null || at.isAfter(newest))) newest = at;
      }
      return (stations: StationDedupe.dedupe(all), at: newest ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// Vùng lưu gần nhất (cho thẻ "Trạm sạc gần nhất" ở Tổng quan). KHÔNG gọi mạng.
  static Future<({List<ChargingStation> stations, DateTime at, double lat, double lng})?> loadLastRegion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regions = await _readRegions(prefs);
      Map<String, dynamic>? best;
      DateTime? bestAt;
      for (final r in regions) {
        final at = DateTime.tryParse('${r['at']}');
        if (at == null) continue;
        if (bestAt == null || at.isAfter(bestAt)) {
          best = r;
          bestAt = at;
        }
      }
      if (best == null || bestAt == null) return null;
      final list = <ChargingStation>[
        for (final e in (best['stations'] as List? ?? const []))
          if (e is Map) ChargingStation.fromJson(Map<String, dynamic>.from(e)),
      ];
      return (
        stations: StationDedupe.dedupe(list),
        at: bestAt,
        lat: (best['lat'] as num).toDouble(),
        lng: (best['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Điểm vào chính ──

  /// Luôn trả về dữ liệu đóng gói + (mạng hoặc cache). [seedLoader] để kiểm thử.
  static Future<StationResult> fetchNear(
    double lat,
    double lng, {
    int radiusM = 8000,
    http.Client? client,
    List<String>? endpoints,
    Duration? timeout,
    Duration? delay,
    Future<List<ChargingStation>> Function()? seedLoader,
  }) async {
    final seed = [
      ...await (seedLoader ?? loadSeed)(),
      // Điểm người dùng đề xuất: luôn cộng đồng + chờ xác minh (xem station_proposal_store.dart).
      for (final p in await StationProposalStore.all()) p.toStation(),
    ];
    final net = await fetchOsm(lat, lng, radiusM, client: client, endpoints: endpoints, timeout: timeout, delay: delay);
    final sources = <String>[if (seed.isNotEmpty) 'Dữ liệu đóng gói / đề xuất cục bộ'];

    if (net.list != null) {
      await saveRegion(lat, lng, net.list!);
      sources.add('OpenStreetMap');
      return StationResult(
        StationDedupe.dedupe([...seed, ...net.list!]),
        fetchedAt: DateTime.now(),
        sources: sources,
      );
    }

    final msg = StationErrors.message(net.error, status: net.status);
    final cache = await loadCache();
    if (cache != null) {
      sources.add('Bộ nhớ đã lưu');
      return StationResult(
        StationDedupe.dedupe([...seed, ...cache.stations]),
        fromCache: true,
        cachedAt: cache.at,
        error: msg,
        errorKind: net.error,
        sources: sources,
      );
    }
    return StationResult(
      StationDedupe.dedupe(seed),
      fromCache: seed.isNotEmpty,
      error: msg,
      errorKind: net.error,
      sources: sources,
    );
  }
}
