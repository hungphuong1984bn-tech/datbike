// Dữ liệu CỤC BỘ của người dùng cho trung tâm trạm sạc: yêu thích, lịch sử tìm
// kiếm, trạm đã dùng và báo cáo. Lưu bằng SharedPreferences nên xem được khi
// mất mạng.
//
// QUY TẮC TRUNG THỰC: báo cáo của người dùng chỉ được LƯU TRÊN MÁY với nhãn
// "chưa xác minh". App không có máy chủ nhận báo cáo, nên không bao giờ coi
// báo cáo là dữ liệu đã xác minh và không tự sửa thông tin trạm theo báo cáo.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/charging_station_service.dart';

enum ReportKind {
  notWorking('Trạm không còn hoạt động'),
  wrongAddress('Địa chỉ không chính xác'),
  noMotorbike('Trạm không hỗ trợ xe máy điện'),
  wrongPower('Thông tin công suất sai'),
  closed('Trạm đã đóng cửa'),
  other('Thông tin cần cập nhật');

  final String label;
  const ReportKind(this.label);
}

class StationReport {
  final String stationId;
  final String stationName;
  final ReportKind kind;
  final String note;
  final DateTime at;

  /// Luôn false: báo cáo của người dùng không phải dữ liệu đã xác minh.
  bool get verified => false;

  const StationReport({
    required this.stationId,
    required this.stationName,
    required this.kind,
    required this.note,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': stationId,
        'name': stationName,
        'kind': kind.name,
        'note': note,
        'at': at.toIso8601String(),
      };

  factory StationReport.fromJson(Map<String, dynamic> j) => StationReport(
        stationId: '${j['id']}',
        stationName: '${j['name'] ?? ''}',
        kind: ReportKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => ReportKind.other,
        ),
        note: '${j['note'] ?? ''}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      );
}

class UsedStation {
  final ChargingStation station;
  final DateTime at;
  const UsedStation(this.station, this.at);
}

class StationUserStore {
  StationUserStore._();

  static const _favKey = 'station_favorites_v1';
  static const _histKey = 'station_search_history_v1';
  static const _usedKey = 'station_used_v1';
  static const _reportKey = 'station_reports_v1';

  static const int maxHistory = 15;
  static const int maxUsed = 30;

  static Future<List<Map<String, dynamic>>> _readList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return [];
      final l = jsonDecode(raw);
      if (l is! List) return [];
      return [for (final e in l) if (e is Map) Map<String, dynamic>.from(e)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeList(String key, List<Object> l) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(l));
    } catch (_) {}
  }

  // ── Yêu thích ──
  static Future<List<ChargingStation>> favorites() async => [
        for (final j in await _readList(_favKey)) ChargingStation.fromJson(j),
      ];

  /// Trả về true nếu sau thao tác trạm đang nằm trong danh sách yêu thích.
  static Future<bool> toggleFavorite(ChargingStation s) async {
    final list = await favorites();
    final i = list.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.insert(0, s);
    }
    await _writeList(_favKey, [for (final e in list) e.toJson()]);
    return i < 0;
  }

  // ── Lịch sử tìm kiếm ──
  static Future<List<String>> history() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_histKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> addHistory(String q) async {
    final t = q.trim();
    if (t.length < 2) return;
    final l = await history();
    l.removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    l.insert(0, t);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_histKey, l.take(maxHistory).toList());
    } catch (_) {}
  }

  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_histKey);
    } catch (_) {}
  }

  // ── Trạm đã dùng (người dùng tự đánh dấu) ──
  static Future<List<UsedStation>> used() async => [
        for (final j in await _readList(_usedKey))
          UsedStation(
            ChargingStation.fromJson(Map<String, dynamic>.from(j['station'] as Map)),
            DateTime.tryParse('${j['at']}') ?? DateTime.now(),
          ),
      ];

  static Future<void> markUsed(ChargingStation s) async {
    final l = await used();
    l.removeWhere((e) => e.station.id == s.id);
    l.insert(0, UsedStation(s, DateTime.now()));
    await _writeList(_usedKey, [
      for (final e in l.take(maxUsed)) {'station': e.station.toJson(), 'at': e.at.toIso8601String()},
    ]);
  }

  // ── Báo cáo (chỉ lưu cục bộ, chưa xác minh) ──
  static Future<List<StationReport>> reports() async => [
        for (final j in await _readList(_reportKey)) StationReport.fromJson(j),
      ];

  static Future<void> addReport(StationReport r) async {
    final l = await reports();
    l.insert(0, r);
    await _writeList(_reportKey, [for (final e in l.take(100)) e.toJson()]);
  }
}
