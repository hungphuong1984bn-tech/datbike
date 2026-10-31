// Xuất / lọc nhật ký BLE — module THUẦN Dart (không I/O, không import Flutter).
//
// Đọc nội dung JSONL do BleLogger ghi, lọc theo thời gian/loại, che dữ liệu
// nhạy cảm rồi xuất JSON hoặc CSV.
//
// Hai mức riêng tư:
//  • shareSafe (mặc định, dùng khi CHIA SẺ): che NGHIÊM NGẶT mọi event — kể cả
//    event không thuộc luồng xác thực (ví dụ event ghi hex của gói thô) — và
//    che chuỗi hex dài/cặp khóa=giá trị trong mọi chuỗi.
//  • full: chỉ áp dụng lớp che mặc định của BleLogger. Có thể còn payload thô;
//    chỉ dành cho nhà phát triển, người dùng phải chủ động chọn.

import 'dart:convert';

import 'connect_diagnostics.dart' show Redactor;

class LogEntry {
  const LogEntry(this.ts, this.type, this.data);

  final DateTime ts;
  final String type;
  final Map<String, Object?> data;
}

class ParsedLog {
  const ParsedLog(this.entries, this.badLines);

  final List<LogEntry> entries;

  /// Số dòng không đọc được (không phải JSON, không phải object, hoặc thiếu `ts` hợp lệ).
  final int badLines;
}

enum ExportPrivacy { shareSafe, full }

extension ExportPrivacyX on ExportPrivacy {
  String get label => this == ExportPrivacy.shareSafe
      ? 'An toàn để chia sẻ (che dữ liệu nhạy cảm)'
      : 'Đầy đủ (có thể chứa dữ liệu gói thô)';
}

class LogExporter {
  LogExporter._();

  /// Đọc JSONL. Dòng hỏng được đếm trong [ParsedLog.badLines], không làm hỏng cả file.
  static ParsedLog parseJsonl(String text) {
    final out = <LogEntry>[];
    var bad = 0;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      try {
        final j = jsonDecode(line);
        if (j is! Map) {
          bad++;
          continue;
        }
        final ts = DateTime.tryParse('${j['ts']}');
        if (ts == null) {
          bad++;
          continue;
        }
        final type = '${j['type'] ?? j['kind'] ?? 'unknown'}';
        final data = <String, Object?>{};
        j.forEach((k, v) {
          if (k != 'ts' && k != 'type') data['$k'] = v;
        });
        out.add(LogEntry(ts, type, data));
      } catch (_) {
        bad++;
      }
    }
    return ParsedLog(out, bad);
  }

  /// Giữ các entry có `from <= ts <= to` (mỗi đầu để null = không giới hạn).
  static List<LogEntry> filterByTime(List<LogEntry> entries,
      {DateTime? from, DateTime? to}) {
    return [
      for (final e in entries)
        if ((from == null || !e.ts.isBefore(from)) &&
            (to == null || !e.ts.isAfter(to)))
          e,
    ];
  }

  /// Giữ các entry có type nằm trong [types]; rỗng/null = giữ tất cả.
  static List<LogEntry> filterByTypes(List<LogEntry> entries, Set<String>? types) {
    if (types == null || types.isEmpty) return List.of(entries);
    return [
      for (final e in entries)
        if (types.contains(e.type)) e,
    ];
  }

  /// Che dữ liệu của một entry theo mức riêng tư.
  static LogEntry sanitize(LogEntry e, ExportPrivacy privacy) {
    final Map<String, Object?> data;
    if (privacy == ExportPrivacy.shareSafe) {
      final strict = Redactor.sanitizeStrict(e.data);
      data = _scrubDeep(strict) as Map<String, Object?>;
    } else {
      data = Redactor.sanitizeEvent(e.type, e.data);
    }
    return LogEntry(e.ts, e.type, data);
  }

  static Object? _scrubDeep(Object? v) {
    if (v is String) return Redactor.scrubText(v);
    if (v is Map) {
      return <String, Object?>{
        for (final e in v.entries) '${e.key}': _scrubDeep(e.value),
      };
    }
    if (v is List) return [for (final x in v) _scrubDeep(x)];
    return v;
  }

  /// Xuất JSON (đã che theo [privacy]).
  static String toJson(
    List<LogEntry> entries, {
    ExportPrivacy privacy = ExportPrivacy.shareSafe,
    DateTime? exportedAt,
    String? appBuild,
    DateTime? from,
    DateTime? to,
    int badLines = 0,
  }) {
    final safe = [for (final e in entries) sanitize(e, privacy)];
    final doc = <String, Object?>{
      'format': 'thbike-ble-log',
      'version': 1,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      if (appBuild != null) 'build': appBuild,
      'privacy': privacy.name,
      'range': {'from': from?.toIso8601String(), 'to': to?.toIso8601String()},
      'count': safe.length,
      'skippedLines': badLines,
      'entries': [
        for (final e in safe)
          {'ts': e.ts.toIso8601String(), 'type': e.type, 'data': e.data},
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Xuất CSV với 3 cột: ts, type, detail (JSON gọn của phần dữ liệu).
  static String toCsv(
    List<LogEntry> entries, {
    ExportPrivacy privacy = ExportPrivacy.shareSafe,
  }) {
    final b = StringBuffer('ts,type,detail\r\n');
    for (final raw in entries) {
      final e = sanitize(raw, privacy);
      b
        ..write(csvCell(e.ts.toIso8601String()))
        ..write(',')
        ..write(csvCell(e.type))
        ..write(',')
        ..write(csvCell(jsonEncode(e.data)))
        ..write('\r\n');
    }
    return b.toString();
  }

  /// Một ô CSV: chống chèn công thức (=, +, -, @, tab, CR ở đầu) và escape đúng chuẩn.
  static String csvCell(String s) {
    var t = s;
    if (t.isNotEmpty && '=+-@\t\r'.contains(t[0])) t = "'$t";
    if (t.contains(',') || t.contains('"') || t.contains('\n') || t.contains('\r')) {
      t = '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }
}
