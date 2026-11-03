// Đồng bộ dữ liệu trạm / log lên máy chủ — KHUNG KẾT NỐI, chưa có Backend.
//
// Dự án hiện chưa có máy chủ nhận dữ liệu trạm sạc. Vì vậy:
//  • [NoStationRemote] báo rõ "chưa cấu hình"; [StationSyncService.syncNow]
//    KHÔNG bao giờ trả về thành công khi chưa gửi thật.
//  • Con trỏ "đã gửi đến đâu" chỉ được đẩy lên SAU khi [StationRemote.push]
//    trả về thành công → không mất bản ghi, không gửi trùng.
//  • Khi có Backend: viết một lớp implements [StationRemote] (HTTPS + token
//    xác thực), gán vào [StationSyncService.remote]. Không phải sửa giao diện.

import 'package:shared_preferences/shared_preferences.dart';

import 'station_log.dart';

abstract class StationRemote {
  /// false nếu chưa cấu hình máy chủ.
  bool get configured;

  /// Gửi một lô bản ghi. Ném lỗi nếu thất bại (không nuốt lỗi).
  Future<void> push(List<Map<String, dynamic>> activity);
}

class NoStationRemote implements StationRemote {
  const NoStationRemote();
  @override
  bool get configured => false;
  @override
  Future<void> push(List<Map<String, dynamic>> activity) async {
    throw StateError('Chưa cấu hình máy chủ đồng bộ.');
  }
}

class SyncStatus {
  final bool configured;
  final int pending;
  final DateTime? lastSyncAt;
  const SyncStatus(this.configured, this.pending, this.lastSyncAt);

  String get message => configured
      ? (pending == 0 ? 'Đã đồng bộ hết.' : '$pending bản ghi chờ đồng bộ.')
      : 'Chưa cấu hình máy chủ — $pending bản ghi chỉ lưu trên thiết bị.';
}

class SyncResult {
  final bool ok;
  final int sent;
  final String message;
  const SyncResult(this.ok, this.sent, this.message);
}

class StationSyncService {
  StationSyncService._();

  static const _cursorKey = 'station_sync_cursor_v1';
  static const _lastKey = 'station_sync_last_v1';
  static const int batchSize = 200;

  /// Gán một implementation thật khi có Backend.
  static StationRemote remote = const NoStationRemote();

  /// Bản ghi mới hơn con trỏ. Hàm thuần.
  static List<StationActivityLog> pendingOf(List<StationActivityLog> logs, DateTime? cursor) =>
      [for (final l in logs) if (cursor == null || l.at.isAfter(cursor)) l];

  static Future<DateTime?> _cursor() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_cursorKey);
      return v == null ? null : DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  static Future<SyncStatus> status() async {
    final logs = await StationLogStore.all();
    final p = await SharedPreferences.getInstance();
    return SyncStatus(
      remote.configured,
      pendingOf(logs, await _cursor()).length,
      DateTime.tryParse(p.getString(_lastKey) ?? ''),
    );
  }

  static Future<SyncResult> syncNow() async {
    if (!remote.configured) {
      return const SyncResult(false, 0, 'Chưa cấu hình máy chủ nên chưa thể đồng bộ. Dữ liệu vẫn an toàn trên thiết bị.');
    }
    try {
      final logs = await StationLogStore.all();
      final todo = pendingOf(logs, await _cursor());
      if (todo.isEmpty) return const SyncResult(true, 0, 'Không có gì cần đồng bộ.');
      var sent = 0;
      final p = await SharedPreferences.getInstance();
      for (var i = 0; i < todo.length; i += batchSize) {
        final chunk = todo.sublist(i, i + batchSize > todo.length ? todo.length : i + batchSize);
        await remote.push([for (final l in chunk) l.toJson()]);
        sent += chunk.length;
        await p.setString(_cursorKey, chunk.last.at.toIso8601String());
      }
      await p.setString(_lastKey, DateTime.now().toIso8601String());
      return SyncResult(true, sent, 'Đã gửi $sent bản ghi.');
    } catch (e) {
      return SyncResult(false, 0, 'Đồng bộ thất bại, sẽ thử lại sau: $e');
    }
  }
}
