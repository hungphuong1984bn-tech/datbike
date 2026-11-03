// Kiểm thử bộ phân tích Regen bằng DỮ LIỆU THẬT do người dùng thu ngày
// 02/11/2026 (test/fixtures/regen_evidence_20261102.json, xe chạy đường vắng,
// đánh dấu các mức Regen 3,4,5,1,2 theo app gốc) và vài chuỗi mô phỏng.
// Kết quả là bằng chứng QUAN SÁT, không phải xác minh giao thức ghi Regen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/regen/regen_analysis.dart';

RegenPoint _p(int ms, double speed, double phase, {double v = 75.0}) =>
    RegenPoint(
      ms: ms,
      speedKmh: speed,
      phaseA: phase,
      voltageV: v,
      powerKw: v * phase / 1000,
    );

void main() {
  late RegenReport real;

  setUpAll(() {
    final json =
        File('test/fixtures/regen_evidence_20261102.json').readAsStringSync();
    real = RegenAnalysis.analyzeEvidenceJson(json);
  });

  group('Dữ liệu thật 02/11/2026', () {
    test('dấu dòng pha: DƯƠNG = nạp ngược (đã kiểm chứng)', () {
      expect(real.sign.positiveIsRegen, isTrue);
      expect(real.sign.correlation, lessThan(-0.7));
      expect(real.sign.decelWhenPositive, greaterThan(0.9));
      expect(real.sign.samples, greaterThan(400));
    });

    test('có đủ 5 mức 1..5, mỗi mức có mẫu nạp', () {
      final labels = real.levels.map((l) => l.label).toList()..sort();
      expect(labels.join(','), equals('1,2,3,4,5'));
      for (final l in real.levels) {
        expect(l.regenSamples, greaterThan(5));
      }
    });

    test('mức 5 nạp mạnh hơn mức 1 rõ rệt (dòng TB và đỉnh)', () {
      final l1 = real.level('1')!;
      final l5 = real.level('5')!;
      expect(l5.meanRegenA, greaterThan(l1.meanRegenA * 2));
      expect(l5.peakA, greaterThan(l1.peakA * 2));
      expect(l5.meanRegenKw, greaterThan(l1.meanRegenKw));
    });

    test('mức 4,5 mạnh hơn mức 3 và mức 1', () {
      final a = real.level('4')!.meanRegenA;
      final b = real.level('5')!.meanRegenA;
      expect(a, greaterThan(real.level('3')!.meanRegenA));
      expect(b, greaterThan(real.level('1')!.meanRegenA));
      expect(real.rankWeakToStrong.first, equals('1'));
      expect(real.rankWeakToStrong.last, equals('5'));
    });

    test('thứ tự mức nhất quán với số mức (Spearman ≥ 0.7)', () {
      expect(real.levelOrderSpearman, isNotNull);
      expect(real.levelOrderSpearman!, greaterThanOrEqualTo(0.7));
    });

    test('tốc độ trung bình lúc nạp các mức gần nhau (so sánh tương đối công bằng)', () {
      final speeds = real.levels.map((l) => l.meanSpeedKmh).toList()..sort();
      expect(speeds.last - speeds.first, lessThan(8.0));
    });

    test('năng lượng thu hồi hợp lý (dương, vài chục Wh trong phiên 8 phút)', () {
      expect(real.totalRecoveredWh, greaterThan(5));
      expect(real.totalRecoveredWh, lessThan(100));
    });

    test('đỉnh dòng nạp không vượt giới hạn quan sát (≈ 45 A)', () {
      for (final l in real.levels) {
        expect(l.peakA, lessThan(45.0));
      }
    });

    test('mức ít đợt nạp bị gắn cảnh báo ít dữ liệu', () {
      expect(real.level('1')!.events, lessThan(2));
      expect(real.level('1')!.lowData, isTrue);
      expect(real.notes.any((n) => n.contains('"1"')), isTrue);
    });

    test('báo cáo xuất JSON được', () {
      final j = real.toJson();
      expect(j['kind'], equals('regen_analysis'));
      expect((j['levels'] as List).length, equals(5));
    });
  });

  group('Chuỗi mô phỏng', () {
    test('dấu ngược (âm = nạp) được nhận ra', () {
      // Chạy 20 km/h; dòng pha DƯƠNG kèm TĂNG tốc, ÂM kèm GIẢM tốc.
      final pts = <RegenPoint>[];
      var t = 0;
      var v = 20.0;
      for (var rep = 0; rep < 12; rep++) {
        for (var i = 0; i < 12; i++) {
          v += 1.2; // tăng tốc
          pts.add(_p(t += 700, v, 15.0 + i));
        }
        for (var i = 0; i < 12; i++) {
          v -= 1.2; // giảm tốc
          pts.add(_p(t += 700, v, -12.0 - i));
        }
      }
      final sign = RegenAnalysis.verifySign(pts);
      expect(sign.positiveIsRegen, isFalse);
    });

    test('quá ít dữ liệu → chưa kết luận, mặc định dương = nạp', () {
      final r = RegenAnalysis.analyze([_p(0, 20, 5), _p(700, 19, 5)], const []);
      expect(r.sign.conclusive, isFalse);
      expect(r.notes.any((n) => n.contains('Chưa kết luận')), isTrue);
    });

    test('đợt nạp: năng lượng ≈ công suất × thời gian', () {
      // 2 kW trong 10 s ≈ 5.56 Wh, xe giảm từ 30 xuống 20 km/h.
      final pts = <RegenPoint>[];
      for (var i = 0; i <= 10; i++) {
        pts.add(RegenPoint(
          ms: i * 1000,
          speedKmh: 30 - i.toDouble(),
          phaseA: 26.7,
          voltageV: 75.0,
          powerKw: 2.0,
        ));
      }
      final ev = RegenAnalysis.findEvents(pts);
      expect(ev.length, equals(1));
      expect(ev.first.energyWh, closeTo(5.56, 0.05));
      expect(ev.first.decelMs2, closeTo(10 / 3.6 / 10, 0.01));
      expect(ev.first.peakKw, closeTo(2.0, 1e-9));
    });

    test('dòng nạp nhỏ (< 3 A) hoặc xe gần đứng yên không tính là nạp', () {
      final pts = [
        for (var i = 0; i < 10; i++) _p(i * 700, 30, 1.5),
        for (var i = 0; i < 10; i++) _p(7000 + i * 700, 2.0, 20),
      ];
      expect(RegenAnalysis.findEvents(pts), isEmpty);
    });

    test('nhiều mốc cùng nhãn được gộp', () {
      final pts = <RegenPoint>[
        for (var i = 0; i < 8; i++) _p(i * 700, 25, 10),
        for (var i = 0; i < 8; i++) _p(20000 + i * 700, 25, 20),
      ];
      final r = RegenAnalysis.analyze(
          pts, const [RegenMark(0, '2'), RegenMark(15000, '2')]);
      expect(r.levels.length, equals(1));
      expect(r.level('2')!.regenSamples, equals(16));
      expect(r.level('2')!.meanRegenA, closeTo(15, 0.01));
    });
  });
}
