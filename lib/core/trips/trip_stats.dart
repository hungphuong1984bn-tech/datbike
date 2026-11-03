// Thống kê hành trình theo Ngày / Tuần / Tháng — thuần Dart, chỉ tính từ
// TripRecord đã lưu (số đo thật). Không có chuyến nào → tất cả bằng 0 / null.

import '../ble/ble_controller.dart' show TripRecord;

enum TripPeriod { day, week, month }

/// Các chuyến thuộc kỳ HIỆN TẠI (hôm nay / tuần này từ thứ Hai / tháng này);
/// [all] = true bỏ lọc. Giữ nguyên thứ tự đầu vào.
List<TripRecord> tripsInCurrentPeriod(
    List<TripRecord> trips, TripPeriod? p, DateTime now) {
  if (p == null) return List.of(trips);
  final d = DateTime(now.year, now.month, now.day);
  final from = switch (p) {
    TripPeriod.day => d,
    TripPeriod.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
    TripPeriod.month => DateTime(now.year, now.month, 1),
  };
  return [for (final t in trips) if (!t.startTime.isBefore(from)) t];
}

class TripBucket {
  final DateTime start; // đầu kỳ (00:00)
  final double km;
  final int trips;
  const TripBucket(this.start, this.km, this.trips);
}

class TripStats {
  final int trips;
  final double totalKm;
  final int totalSec;
  final double? avgSpeedKmh; // trung bình có trọng số theo thời gian; null nếu chưa có
  final double maxSpeedKmh;
  final List<TripBucket> buckets; // cũ → mới, đủ số kỳ (kỳ trống = 0)

  const TripStats({
    required this.trips,
    required this.totalKm,
    required this.totalSec,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.buckets,
  });

  /// Ngày: 7 ngày gần nhất · Tuần: 8 tuần (bắt đầu thứ Hai) · Tháng: 6 tháng.
  static TripStats compute(List<TripRecord> all, TripPeriod p, DateTime now) {
    final starts = <DateTime>[];
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    switch (p) {
      case TripPeriod.day:
        final t = day(now);
        for (var i = 6; i >= 0; i--) {
          starts.add(DateTime(t.year, t.month, t.day - i));
        }
        break;
      case TripPeriod.week:
        final t = day(now);
        final mon = DateTime(t.year, t.month, t.day - (t.weekday - 1));
        for (var i = 7; i >= 0; i--) {
          starts.add(DateTime(mon.year, mon.month, mon.day - 7 * i));
        }
        break;
      case TripPeriod.month:
        for (var i = 5; i >= 0; i--) {
          starts.add(DateTime(now.year, now.month - i, 1));
        }
        break;
    }
    DateTime end(DateTime s) {
      switch (p) {
        case TripPeriod.day:
          return DateTime(s.year, s.month, s.day + 1);
        case TripPeriod.week:
          return DateTime(s.year, s.month, s.day + 7);
        case TripPeriod.month:
          return DateTime(s.year, s.month + 1, 1);
      }
    }

    final from = starts.first;
    final to = end(starts.last);
    final km = List<double>.filled(starts.length, 0);
    final n = List<int>.filled(starts.length, 0);
    var totalKm = 0.0, maxV = 0.0;
    var sec = 0, count = 0;
    for (final r in all) {
      final t = r.startTime;
      if (t.isBefore(from) || !t.isBefore(to)) continue;
      var idx = -1;
      for (var i = 0; i < starts.length; i++) {
        if (!t.isBefore(starts[i]) && t.isBefore(end(starts[i]))) {
          idx = i;
          break;
        }
      }
      if (idx < 0) continue;
      km[idx] += r.distanceKm;
      n[idx] += 1;
      totalKm += r.distanceKm;
      sec += r.durationSec;
      count += 1;
      if (r.maxSpeedKmh > maxV) maxV = r.maxSpeedKmh;
    }
    return TripStats(
      trips: count,
      totalKm: totalKm,
      totalSec: sec,
      avgSpeedKmh: sec > 0 ? totalKm / (sec / 3600.0) : null,
      maxSpeedKmh: maxV,
      buckets: [
        for (var i = 0; i < starts.length; i++) TripBucket(starts[i], km[i], n[i])
      ],
    );
  }
}
