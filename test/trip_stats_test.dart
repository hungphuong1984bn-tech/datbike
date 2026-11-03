import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_controller.dart' show TripRecord;
import 'package:mybike_app/core/trips/trip_stats.dart';

TripRecord _t(DateTime s, double km, int sec, double max) => TripRecord(
      startTime: s,
      endTime: s.add(Duration(seconds: sec)),
      distanceKm: km,
      durationSec: sec,
      avgSpeedKmh: 0,
      maxSpeedKmh: max,
      usedPercent: 1,
    );

void main() {
  tripsInPeriodTests();
  final now = DateTime(2026, 11, 3, 10); // thứ Ba
  test('rỗng → 0 chuyến, avg null, đủ kỳ', () {
    final s = TripStats.compute(const [], TripPeriod.day, now);
    expect(s.trips, 0);
    expect(s.avgSpeedKmh, isNull);
    expect(s.buckets.length, 7);
  });
  test('ngày: gộp đúng và bỏ chuyến ngoài khoảng', () {
    final s = TripStats.compute([
      _t(DateTime(2026, 11, 3, 8), 10, 1800, 50),
      _t(DateTime(2026, 11, 3, 9), 5, 900, 60),
      _t(DateTime(2026, 10, 1), 99, 100, 99),
    ], TripPeriod.day, now);
    expect(s.trips, 2);
    expect(s.totalKm, 15);
    expect(s.buckets.last.km, 15);
    expect(s.avgSpeedKmh, closeTo(20, 1e-9));
    expect(s.maxSpeedKmh, 60);
  });
  test('tuần bắt đầu thứ Hai, tháng 6 kỳ', () {
    final w = TripStats.compute([_t(DateTime(2026, 11, 2, 7), 3, 600, 30)], TripPeriod.week, now);
    expect(w.buckets.last.start, DateTime(2026, 11, 2));
    expect(w.buckets.last.km, 3);
    final m = TripStats.compute([_t(DateTime(2026, 6, 20), 7, 600, 30)], TripPeriod.month, now);
    expect(m.buckets.length, 6);
    expect(m.buckets.first.start, DateTime(2026, 6, 1));
    expect(m.buckets.first.km, 7);
  });
}

void tripsInPeriodTests() {
  final now = DateTime(2026, 11, 3, 10);
  final a = _t(DateTime(2026, 11, 3, 8), 1, 60, 1); // hôm nay
  final b = _t(DateTime(2026, 11, 2, 8), 1, 60, 1); // thứ Hai
  final c = _t(DateTime(2026, 11, 1, 8), 1, 60, 1); // Chủ nhật tuần trước
  final d = _t(DateTime(2026, 10, 31, 8), 1, 60, 1);
  test('tripsInCurrentPeriod', () {
    final all = [a, b, c, d];
    expect(tripsInCurrentPeriod(all, TripPeriod.day, now), [a]);
    expect(tripsInCurrentPeriod(all, TripPeriod.week, now), [a, b]);
    expect(tripsInCurrentPeriod(all, TripPeriod.month, now), [a, b, c]);
    expect(tripsInCurrentPeriod(all, null, now), all);
  });
}
