// Lịch sử thông số vận hành theo thời gian — thuần Dart, chỉ lưu giá trị đo thật.
// Mẫu thưa tối thiểu [interval]; giữ [capacity] mẫu gần nhất (≈ 10 phút).
// Nhiệt độ == 0 được coi là "xe chưa báo" và KHÔNG đưa vào biểu đồ.

import '../battery/battery_history.dart' show Series;

class OpsHistory {
  static const Duration interval = Duration(seconds: 2);
  static const int capacity = 300;

  final Series speed = Series(capacity);
  final Series voltage = Series(capacity);
  final Series phaseA = Series(capacity);
  final Series powerW = Series(capacity);
  final Series bmsTemp = Series(capacity);
  final Series ecuTemp = Series(capacity);
  final Series motorTemp = Series(capacity);

  DateTime? _lastAt;

  List<Series> get all =>
      [speed, voltage, phaseA, powerW, bmsTemp, ecuTemp, motorTemp];

  void clear() {
    for (final s in all) {
      s.clear();
    }
    _lastAt = null;
  }

  /// Trả về true nếu mẫu được ghi (đủ khoảng cách thời gian).
  bool add({
    required DateTime at,
    required double speedKmh,
    required double voltageV,
    required double phaseAmps,
    required double bmsC,
    required double ecuC,
    required double motorC,
  }) {
    final last = _lastAt;
    if (last != null && at.difference(last) < interval) return false;
    _lastAt = at;
    speed.add(at, speedKmh);
    phaseA.add(at, phaseAmps);
    if (voltageV > 0) {
      voltage.add(at, voltageV);
      powerW.add(at, voltageV * phaseAmps.abs());
    }
    if (bmsC > 0) bmsTemp.add(at, bmsC);
    if (ecuC > 0) ecuTemp.add(at, ecuC);
    if (motorC > 0) motorTemp.add(at, motorC);
    return true;
  }
}

class SeriesStats {
  final double min;
  final double avg;
  final double max;
  const SeriesStats(this.min, this.avg, this.max);

  static SeriesStats? of(List<double> v) {
    if (v.isEmpty) return null;
    var lo = v.first, hi = v.first, sum = 0.0;
    for (final x in v) {
      if (x < lo) lo = x;
      if (x > hi) hi = x;
      sum += x;
    }
    return SeriesStats(lo, sum / v.length, hi);
  }
}
