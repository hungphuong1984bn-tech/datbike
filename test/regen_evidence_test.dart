// Kiểm thử phần thuần của mô-đun thu thập bằng chứng Regen (chỉ đọc).

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/regen/regen_evidence.dart';

EvidenceSample s(int ms, double speed, double phase, {double v = 70}) => EvidenceSample(
      ms: ms,
      speedKmh: speed,
      phaseA: phase,
      voltageV: v,
      powerKw: v * phase / 1000.0,
      throttle: 0,
      adc1: 0,
      adc2: 0,
      stateIndex: 3,
      percent: 80,
      error: 0,
      sideStand: false,
    );

void main() {
  group('summarizeSegments', () {
    test('cắt theo mốc và báo cả cực tiểu lẫn cực đại', () {
      final samples = [s(0, 20, -5), s(500, 18, -10), s(1000, 15, 8), s(1500, 10, 12)];
      final marks = [const EvidenceMark(0, 'Mức 1', ''), const EvidenceMark(1000, 'Mức 2', 'nhả ga')];
      final r = summarizeSegments(samples, marks);
      expect(r.length, 2);
      expect(r[0].sampleCount, 2);
      expect(r[0].phaseMinA, -10);
      expect(r[0].phaseMaxA, -5);
      expect(r[1].sampleCount, 2);
      expect(r[1].phaseMaxA, 12);
      expect(r[1].speedStartKmh, 15);
      expect(r[1].speedEndKmh, 10);
    });

    test('mốc không có mẫu → sampleCount 0, không lỗi', () {
      final r = summarizeSegments(const [], [const EvidenceMark(0, 'X', '')]);
      expect(r.single.sampleCount, 0);
      expect(r.single.phaseMinA, isNull);
    });
  });

  group('diffSnapshots', () {
    test('chỉ trả char đổi giá trị', () {
      final d = diffSnapshots(
        {'a': '01', 'b': '02', 'c': '03'},
        {'a': '01', 'b': '05', 'c': '03', 'd': '09'},
        names: {'b': 'Tên B'},
      );
      expect(d.map((e) => e.uuid), ['b', 'd']);
      expect(d.first.name, 'Tên B');
      expect(d.first.before, '02');
      expect(d.first.after, '05');
      expect(d.last.before, isNull);
    });

    test('lỗi đọc ở cả hai phía không tính là đổi', () {
      final d = diffSnapshots({'a': 'ERR: timeout'}, {'a': 'ERR: không có phản hồi'});
      expect(d, isEmpty);
    });

    test('đọc được → lỗi tính là đổi', () {
      final d = diffSnapshots({'a': '01'}, {'a': 'ERR: x'});
      expect(d.length, 1);
    });
  });

  group('xuất dữ liệu', () {
    test('CSV có tiêu đề, gắn nhãn mốc gần nhất', () {
      final csv = evidenceToCsv(
        [s(0, 10, -1), s(2000, 12, 3)],
        [const EvidenceMark(1000, 'Mức "2"', '')],
      );
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('ms,speed_kmh,phase_a'));
      expect(lines[1].endsWith(',""'), isTrue); // trước mốc đầu: không nhãn
      expect(lines[2], contains("Mức '2'")); // dấu " được thay để không vỡ CSV
    });

    test('JSON ghi rõ chỉ đọc và có danh sách thay đổi', () {
      final j = evidenceToJson(
        startedAt: DateTime(2026, 11, 1),
        samples: [s(0, 10, -1)],
        marks: const [],
        changes: const [CharChange('abcd', 'Tên', '01', '02')],
      );
      expect(j, contains('Chỉ đọc'));
      expect(j, contains('characteristicChanges'));
      expect(j, contains('"after": "02"'));
    });
  });
}
