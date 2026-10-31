// Test xuất/lọc nhật ký BLE — Unit Test.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/connect_diagnostics.dart' show Redactor;
import 'package:mybike_app/core/ble/log_export.dart';

const _jsonl = '''
{"ts":"2026-10-31T10:00:00.000","type":"session_start","app":"thbike_flutter"}
{"ts":"2026-10-31T10:05:00.000","type":"connected","device_id":"AA:BB"}
not json at all
{"ts":"2026-10-31T10:10:00.000","type":"notify","uuid":"1234","len":4,"hex":"de ad be ef"}
{"ts":"2026-10-31T11:00:00.000","type":"auto_handshake_failed","kind":"authRejected","token":"c97eb99d-secret"}
[1,2,3]
{"type":"no_ts"}

{"ts":"2026-10-31T11:30:00.000","kind":"crash","error":"password=hunter22 boom"}
''';

void main() {
  setUp(Redactor.clearSecretsForTest);

  group('parseJsonl', () {
    test('đọc dòng hợp lệ, đếm dòng hỏng', () {
      final p = LogExporter.parseJsonl(_jsonl);
      expect(p.entries.length, 5);
      expect(p.badLines, 3); // not json, mảng, thiếu ts
      expect(p.entries.first.type, 'session_start');
      expect(p.entries.first.data.containsKey('ts'), isFalse);
      expect(p.entries.first.data['app'], 'thbike_flutter');
    });
    test('dòng thiếu type dùng kind (app_errors.jsonl)', () {
      final p = LogExporter.parseJsonl(_jsonl);
      expect(p.entries.last.type, 'crash');
    });
    test('rỗng', () {
      final p = LogExporter.parseJsonl('');
      expect(p.entries, isEmpty);
      expect(p.badLines, 0);
    });
  });

  group('lọc', () {
    final all = LogExporter.parseJsonl(_jsonl).entries;
    test('theo khoảng thời gian (bao gồm hai đầu)', () {
      final r = LogExporter.filterByTime(all,
          from: DateTime.parse('2026-10-31T10:05:00.000'),
          to: DateTime.parse('2026-10-31T11:00:00.000'));
      expect(r.map((e) => e.type).toList(),
          ['connected', 'notify', 'auto_handshake_failed']);
    });
    test('chỉ from / chỉ to / không giới hạn', () {
      expect(LogExporter.filterByTime(all).length, all.length);
      expect(
          LogExporter.filterByTime(all, from: DateTime.parse('2026-10-31T11:00:00.000'))
              .length,
          2);
      expect(
          LogExporter.filterByTime(all, to: DateTime.parse('2026-10-31T10:00:00.000'))
              .length,
          1);
    });
    test('theo loại', () {
      expect(LogExporter.filterByTypes(all, {'notify'}).length, 1);
      expect(LogExporter.filterByTypes(all, {}).length, all.length);
      expect(LogExporter.filterByTypes(all, null).length, all.length);
    });
  });

  group('che dữ liệu nhạy cảm', () {
    final all = LogExporter.parseJsonl(_jsonl).entries;

    test('shareSafe che hex của event KHÔNG thuộc luồng xác thực (notify)', () {
      final notify = all.firstWhere((e) => e.type == 'notify');
      final safe = LogExporter.sanitize(notify, ExportPrivacy.shareSafe);
      expect(safe.data['hex'], '«redacted»');
      expect(safe.data['len'], 4);
    });
    test('full giữ hex của event không xác thực (hành vi log hiện có)', () {
      final notify = all.firstWhere((e) => e.type == 'notify');
      final full = LogExporter.sanitize(notify, ExportPrivacy.full);
      expect(full.data['hex'], 'de ad be ef');
    });
    test('token bị che ở cả hai mức với event xác thực', () {
      final e = all.firstWhere((e) => e.type == 'auto_handshake_failed');
      expect(LogExporter.sanitize(e, ExportPrivacy.shareSafe).data['token'], '«redacted»');
      expect(LogExporter.sanitize(e, ExportPrivacy.full).data['token'], '«redacted»');
    });
    test('shareSafe che cặp password=... trong chuỗi tự do', () {
      final e = all.last;
      final safe = LogExporter.sanitize(e, ExportPrivacy.shareSafe);
      expect('${safe.data['error']}', isNot(contains('hunter22')));
    });
    test('shareSafe che chuỗi hex dài trong giá trị lồng nhau', () {
      final long = 'ab' * 20;
      final e = LogEntry(DateTime(2026), 'x', {
        'note': 'v=$long',
        'nested': {
          'list': ['k=$long']
        },
      });
      final out = jsonEncode(LogExporter.sanitize(e, ExportPrivacy.shareSafe).data);
      expect(out, isNot(contains(long)));
    });
    test('bí mật đã đăng ký không lọt ra JSON/CSV ở cả hai mức', () {
      Redactor.registerSecret('S3cretPIN99');
      final e = LogEntry(DateTime(2026), 'misc', {'msg': 'pin la S3cretPIN99 nhe'});
      for (final p in ExportPrivacy.values) {
        expect(LogExporter.toJson([e], privacy: p), isNot(contains('S3cretPIN99')));
        expect(LogExporter.toCsv([e], privacy: p), isNot(contains('S3cretPIN99')));
      }
    });
  });

  group('JSON', () {
    test('cấu trúc, đếm, khoảng thời gian, số dòng bỏ qua', () {
      final p = LogExporter.parseJsonl(_jsonl);
      final from = DateTime.parse('2026-10-31T10:00:00.000');
      final out = LogExporter.toJson(p.entries,
          exportedAt: DateTime.parse('2026-10-31T12:00:00.000'),
          appBuild: 'b1',
          from: from,
          badLines: p.badLines);
      final j = jsonDecode(out) as Map<String, dynamic>;
      expect(j['format'], 'thbike-ble-log');
      expect(j['version'], 1);
      expect(j['privacy'], 'shareSafe');
      expect(j['count'], 5);
      expect(j['skippedLines'], 3);
      expect(j['build'], 'b1');
      expect((j['range'] as Map)['from'], from.toIso8601String());
      final first = (j['entries'] as List).first as Map;
      expect(first['type'], 'session_start');
      expect(first.containsKey('data'), isTrue);
    });
    test('danh sách rỗng vẫn hợp lệ', () {
      final j = jsonDecode(LogExporter.toJson([])) as Map<String, dynamic>;
      expect(j['count'], 0);
      expect(j['entries'], isEmpty);
    });
  });

  group('CSV', () {
    test('tiêu đề và số dòng', () {
      final p = LogExporter.parseJsonl(_jsonl);
      final csv = LogExporter.toCsv(p.entries);
      final lines = csv.split('\r\n').where((l) => l.isNotEmpty).toList();
      expect(lines.first, 'ts,type,detail');
      expect(lines.length, 1 + p.entries.length);
    });
    test('escape dấu phẩy, nháy kép, xuống dòng', () {
      expect(LogExporter.csvCell('a,b'), '"a,b"');
      expect(LogExporter.csvCell('say "hi"'), '"say ""hi"""');
      expect(LogExporter.csvCell('l1\nl2'), '"l1\nl2"');
      expect(LogExporter.csvCell('plain'), 'plain');
    });
    test('chống chèn công thức', () {
      expect(LogExporter.csvCell('=1+1'), "'=1+1");
      expect(LogExporter.csvCell('+cmd'), "'+cmd");
      expect(LogExporter.csvCell('-5'), "'-5");
      expect(LogExporter.csvCell('@SUM(A1)'), "'@SUM(A1)");
    });
    test('cột detail là JSON đọc lại được', () {
      final e = LogEntry(DateTime(2026, 10, 31), 'x', {'a': 1, 'b': 'c,d'});
      final csv = LogExporter.toCsv([e]);
      expect(csv, contains('"{""a"":1,""b"":""c,d""}"'));
    });
  });
}
