// Nhật ký hoạt động liên quan đến trạm sạc — nền tảng dữ liệu để phát triển
// mạng lưới trạm.
//
// NGUYÊN TẮC RIÊNG TƯ
//  • Chỉ ghi khi người dùng ĐANG dùng màn Trạm sạc. Không ghi tọa độ nền.
//  • Mã người dùng là chuỗi ngẫu nhiên ẩn danh, KHÔNG gắn tài khoản/số điện thoại.
//  • Tọa độ khu vực chỉ được ghi khi người dùng đồng ý ([StationLogConsent.area]),
//    và luôn làm tròn ~1 km ([coarse]) — không lưu vị trí chính xác.
//  • Log nằm trên thiết bị. Chưa có máy chủ nhận log → xem station_sync.dart; app
//    không bao giờ báo "đã đồng bộ" khi chưa gửi thật.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

enum StationEvent {
  view('Xem trạm'),
  search('Tìm kiếm'),
  filter('Lọc'),
  detail('Xem chi tiết'),
  navigate('Nhấn Dẫn đường'),
  navigateResult('Kết quả mở Google Maps'),
  emptyResult('Khu vực không có trạm'),
  propose('Gửi đề xuất trạm'),
  mapError('Lỗi tải bản đồ/dữ liệu'),
  gpsError('Lỗi GPS');

  final String label;
  const StationEvent(this.label);

  static StationEvent? byName(Object? n) {
    for (final e in values) {
      if (e.name == n) return e;
    }
    return null;
  }
}

/// Làm tròn tọa độ ~1,1 km (2 chữ số thập phân) để không lộ vị trí chính xác.
double coarse(double v) => (v * 100).round() / 100;

class StationActivityLog {
  final StationEvent event;
  final DateTime at;
  final String anonId;
  final String? stationId;
  final String? query;
  final double? distanceKm;
  final double? areaLat;
  final double? areaLng;
  final String? detail;

  const StationActivityLog({
    required this.event,
    required this.at,
    required this.anonId,
    this.stationId,
    this.query,
    this.distanceKm,
    this.areaLat,
    this.areaLng,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'e': event.name,
        't': at.toIso8601String(),
        'u': anonId,
        if (stationId != null) 's': stationId,
        if (query != null) 'q': query,
        if (distanceKm != null) 'd': double.parse(distanceKm!.toStringAsFixed(2)),
        if (areaLat != null) 'la': areaLat,
        if (areaLng != null) 'ln': areaLng,
        if (detail != null) 'x': detail,
      };

  static StationActivityLog? fromJson(Object? o) {
    if (o is! Map) return null;
    final ev = StationEvent.byName(o['e']);
    final at = DateTime.tryParse('${o['t']}');
    if (ev == null || at == null) return null;
    return StationActivityLog(
      event: ev,
      at: at,
      anonId: '${o['u'] ?? ''}',
      stationId: o['s'] as String?,
      query: o['q'] as String?,
      distanceKm: (o['d'] as num?)?.toDouble(),
      areaLat: (o['la'] as num?)?.toDouble(),
      areaLng: (o['ln'] as num?)?.toDouble(),
      detail: o['x'] as String?,
    );
  }
}

/// Sự đồng ý của người dùng. Mặc định KHÔNG ghi tọa độ khu vực.
class StationLogConsent {
  StationLogConsent._();

  static const _areaKey = 'station_log_area_consent_v1';
  static const _askedKey = 'station_log_area_asked_v1';

  static Future<bool> area() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_areaKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Đã hỏi người dùng chưa (để chỉ hiện lời hỏi một lần).
  static Future<bool> asked() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_askedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setArea(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_areaKey, v);
      await p.setBool(_askedKey, true);
      StationLogStore._areaConsent = v;
    } catch (_) {}
  }
}

class StationLogStore {
  StationLogStore._();

  static const _key = 'station_activity_v1';
  static const _idKey = 'station_anon_id_v1';

  /// Giới hạn bộ nhớ: bản ghi cũ nhất bị bỏ khi vượt.
  static const int maxEntries = 5000;

  static List<StationActivityLog>? _cache;
  static String? _anon;
  static bool? _areaConsent;
  static Timer? _flushTimer;

  /// Chỉ cho kiểm thử: đặt lại trạng thái bộ nhớ.
  static void resetForTest() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _cache = null;
    _anon = null;
    _areaConsent = null;
  }

  static Future<String> anonId() async {
    if (_anon != null) return _anon!;
    try {
      final p = await SharedPreferences.getInstance();
      var id = p.getString(_idKey);
      if (id == null || id.isEmpty) {
        final r = math.Random.secure();
        id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
        await p.setString(_idKey, id);
      }
      return _anon = id;
    } catch (_) {
      return _anon = 'anon';
    }
  }

  static Future<List<StationActivityLog>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final l = jsonDecode(raw);
        if (l is List) {
          return _cache = [
            for (final e in l) ?StationActivityLog.fromJson(e),
          ];
        }
      }
    } catch (_) {}
    return _cache = <StationActivityLog>[];
  }

  static Future<List<StationActivityLog>> all() async => List.of(await _load());

  /// Ghi một sự kiện. Không bao giờ ném lỗi (log không được làm hỏng chức năng chính).
  /// [areaLat]/[areaLng] bị BỎ nếu người dùng chưa đồng ý, và luôn được làm tròn.
  static Future<void> record(
    StationEvent event, {
    String? stationId,
    String? query,
    double? distanceKm,
    double? areaLat,
    double? areaLng,
    String? detail,
    DateTime? now,
  }) async {
    try {
      _areaConsent ??= await StationLogConsent.area();
      final okArea = _areaConsent == true && areaLat != null && areaLng != null;
      final q = query?.trim();
      final log = StationActivityLog(
        event: event,
        at: now ?? DateTime.now(),
        anonId: await anonId(),
        stationId: stationId,
        query: (q == null || q.isEmpty) ? null : (q.length > 80 ? q.substring(0, 80) : q),
        distanceKm: distanceKm,
        areaLat: okArea ? coarse(areaLat) : null,
        areaLng: okArea ? coarse(areaLng) : null,
        detail: (detail != null && detail.length > 160) ? detail.substring(0, 160) : detail,
      );
      final l = await _load();
      l.add(log);
      if (l.length > maxEntries) l.removeRange(0, l.length - maxEntries);
      _scheduleFlush();
    } catch (_) {}
  }

  static void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), flush);
  }

  /// Ghi xuống đĩa ngay (gọi khi rời màn hình).
  static Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final l = _cache;
    if (l == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final e in l) e.toJson()]));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cache = <StationActivityLog>[];
    await flush();
  }

  static Future<String> exportJson() async => const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'note': 'Nhật ký ẩn danh trên thiết bị; tọa độ làm tròn ~1 km và chỉ có khi người dùng đồng ý.',
        'logs': [for (final e in await all()) e.toJson()],
      });
}

// ═════════════ Lịch sử thay đổi dữ liệu trạm ═════════════

enum ChangeAction {
  create('Tạo'),
  update('Sửa'),
  delete('Xóa'),
  hide('Ẩn'),
  show('Hiện'),
  verify('Xác minh'),
  unverify('Bỏ xác minh'),
  approve('Duyệt đề xuất'),
  reject('Từ chối đề xuất');

  final String label;
  const ChangeAction(this.label);

  static ChangeAction byName(Object? n) {
    for (final e in values) {
      if (e.name == n) return e;
    }
    return ChangeAction.update;
  }
}

class StationChangeLog {
  final String stationId;
  final String stationName;
  final ChangeAction action;
  final DateTime at;
  final String actor;

  /// Trường → [giá trị cũ, giá trị mới] (null = không có).
  final Map<String, List<String?>> changes;
  final String source;

  const StationChangeLog({
    required this.stationId,
    required this.stationName,
    required this.action,
    required this.at,
    required this.actor,
    this.changes = const {},
    this.source = 'Quản trị viên (cục bộ)',
  });

  Map<String, dynamic> toJson() => {
        'id': stationId,
        'name': stationName,
        'a': action.name,
        't': at.toIso8601String(),
        'by': actor,
        'src': source,
        'c': {for (final e in changes.entries) e.key: e.value},
      };

  static StationChangeLog? fromJson(Object? o) {
    if (o is! Map) return null;
    final at = DateTime.tryParse('${o['t']}');
    if (at == null) return null;
    final ch = <String, List<String?>>{};
    final c = o['c'];
    if (c is Map) {
      for (final e in c.entries) {
        final v = e.value;
        if (v is List && v.length == 2) ch['${e.key}'] = [v[0]?.toString(), v[1]?.toString()];
      }
    }
    return StationChangeLog(
      stationId: '${o['id']}',
      stationName: '${o['name'] ?? ''}',
      action: ChangeAction.byName(o['a']),
      at: at,
      actor: '${o['by'] ?? ''}',
      changes: ch,
      source: '${o['src'] ?? ''}',
    );
  }
}
