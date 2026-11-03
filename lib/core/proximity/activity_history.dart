// Lịch sử hoạt động Smart Key — LƯU BỀN (SharedPreferences), thuần Dart ở phần logic.
// Chỉ lưu sự kiện THẬT do ProximityEngine ghi. Không lưu RSSI thô từng mẫu
// (bỏ sự kiện "zone" dồn dập) và không có thông tin xác thực/khóa phiên.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'proximity_engine.dart' show ProximityEvent;

enum ActivityKind { unlock, lock, error, calibration, other }

extension ActivityKindLabel on ActivityKind {
  String get label => switch (this) {
        ActivityKind.unlock => 'Mở khóa',
        ActivityKind.lock => 'Khóa',
        ActivityKind.error => 'Lỗi',
        ActivityKind.calibration => 'Hiệu chỉnh',
        ActivityKind.other => 'Khác',
      };
}

/// Phân loại theo tên sự kiện của engine (unlock_ok, lock_fail, calibrate_start…).
ActivityKind classifyActivity(String kind) {
  if (kind.endsWith('_fail')) return ActivityKind.error;
  if (kind.startsWith('calibrate')) return ActivityKind.calibration;
  if (kind.startsWith('armed')) return ActivityKind.other;
  if (kind == 'user_lock') return ActivityKind.lock;
  if (kind.startsWith('unlock')) return ActivityKind.unlock;
  if (kind.startsWith('lock')) return ActivityKind.lock;
  return ActivityKind.other;
}

/// Sự kiện nào đáng lưu bền? Bỏ "zone" (đổi vùng liên tục, dễ tràn bộ nhớ).
bool isPersistable(ProximityEvent e) => e.kind != 'zone';

String? describeActivity(ProximityEvent e) => e.detail.isEmpty ? null : e.detail;

class ActivityHistory {
  static const int capacity = 200;
  static const String _key = 'prox_activity_history_v1';

  /// Mã hóa danh sách (cũ → mới), cắt còn [capacity] mục mới nhất.
  static String encode(List<ProximityEvent> events) {
    final tail = events.length > capacity
        ? events.sublist(events.length - capacity)
        : events;
    return jsonEncode([
      for (final e in tail)
        {'t': e.at.millisecondsSinceEpoch, 'k': e.kind, 'd': e.detail}
    ]);
  }

  /// Giải mã an toàn: dữ liệu hỏng → danh sách rỗng, mục lỗi bị bỏ qua.
  static List<ProximityEvent> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      final out = <ProximityEvent>[];
      for (final m in j) {
        if (m is Map && m['t'] is int && m['k'] is String) {
          out.add(ProximityEvent(
            DateTime.fromMillisecondsSinceEpoch(m['t'] as int),
            m['k'] as String,
            m['d'] is String ? m['d'] as String : '',
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ProximityEvent>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return decode(p.getString(_key));
    } catch (_) {
      return const [];
    }
  }

  /// Nối thêm sự kiện mới (đã lọc) rồi ghi lại. Lỗi ghi bị bỏ qua (best-effort).
  static Future<void> append(List<ProximityEvent> fresh) async {
    final add = fresh.where(isPersistable).toList();
    if (add.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final cur = decode(p.getString(_key))..addAll(add);
      await p.setString(_key, encode(cur));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}
