// Battery History — lịch sử điện áp/cell và pack, giới hạn bộ nhớ.
// Chỉ lưu trong RAM của phiên chạy hiện tại (không ghi đĩa).

import 'cell_model.dart';

/// Chuỗi (thời gian, giá trị) có dung lượng tối đa. Dùng cắt theo lô để chi phí
/// trung bình mỗi lần thêm là O(1).
class Series {
  final int capacity;
  final List<int> _t = <int>[];
  final List<double> _v = <double>[];

  Series(this.capacity);

  int get length => _v.length;
  bool get isEmpty => _v.isEmpty;

  void add(DateTime at, double value) {
    if (!value.isFinite) return;
    _t.add(at.millisecondsSinceEpoch);
    _v.add(value);
    final overflow = _v.length - capacity;
    if (overflow > capacity ~/ 4) {
      _t.removeRange(0, overflow);
      _v.removeRange(0, overflow);
    }
  }

  void clear() {
    _t.clear();
    _v.clear();
  }

  int get _start => _v.length > capacity ? _v.length - capacity : 0;

  /// Bản sao các giá trị (tối đa [capacity] mẫu gần nhất).
  List<double> values() => List<double>.of(_v.sublist(_start));

  List<DateTime> times() => _t
      .sublist(_start)
      .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms))
      .toList(growable: false);

  double? get last => _v.isEmpty ? null : _v.last;
}

class CellExtreme {
  final double voltage;
  final DateTime at;
  const CellExtreme(this.voltage, this.at);
}

/// Xu hướng lệch kéo dài của một cell so với trung bình.
class CellTrend {
  final int cellIndex;
  final double meanDeviationMv;
  final int samples;
  const CellTrend(this.cellIndex, this.meanDeviationMv, this.samples);
}

class BatteryHistory {
  /// Mỗi gói BMS (~2 giây/gói): giữ 300 mẫu ≈ 10 phút.
  static const int shortCapacity = 300;

  /// Mẫu thưa, tối thiểu 30 giây/mẫu: giữ 240 mẫu ≈ 2 giờ.
  static const int longCapacity = 240;
  static const Duration longInterval = Duration(seconds: 30);

  int _cellCount = 0;
  List<Series> _cellShort = <Series>[];
  List<Series> _cellLong = <Series>[];
  List<Series> _cellDev = <Series>[]; // độ lệch so với TB (mV), để xét xu hướng
  List<CellExtreme?> _cellMax = <CellExtreme?>[];
  List<CellExtreme?> _cellMin = <CellExtreme?>[];
  DateTime? _lastLongAt;

  final Series packVoltage = Series(shortCapacity);
  final Series packCurrent = Series(shortCapacity);
  final Series deltaMv = Series(shortCapacity);
  final Series avgCell = Series(shortCapacity);
  final Series avgCellLong = Series(longCapacity);
  final Series deltaLong = Series(longCapacity);

  int get cellCount => _cellCount;

  /// Số lần số cell thay đổi giữa hai gói liên tiếp (lịch sử cell bị reset).
  int resetCount = 0;

  /// Thêm một gói BMS. Trả về true nếu số cell thay đổi nên lịch sử cell bị reset.
  bool add(PackSnapshot s) {
    var reset = false;
    if (s.cellCount != _cellCount) {
      reset = _cellCount != 0;
      _resetCells(s.cellCount);
      if (reset) resetCount++;
    }

    final at = s.receivedAt;
    final longDue =
        _lastLongAt == null || at.difference(_lastLongAt!) >= longInterval;
    if (longDue) _lastLongAt = at;

    for (final c in s.cells) {
      if (!c.valid) continue;
      _cellShort[c.index].add(at, c.voltage);
      _cellDev[c.index].add(at, c.deviationMv);
      if (longDue) _cellLong[c.index].add(at, c.voltage);

      final mx = _cellMax[c.index];
      if (mx == null || c.voltage > mx.voltage) {
        _cellMax[c.index] = CellExtreme(c.voltage, at);
      }
      final mn = _cellMin[c.index];
      if (mn == null || c.voltage < mn.voltage) {
        _cellMin[c.index] = CellExtreme(c.voltage, at);
      }
    }

    if (s.packVoltage > 0) packVoltage.add(at, s.packVoltage);
    packCurrent.add(at, s.current);
    if (s.hasStats) {
      avgCell.add(at, s.vAvg);
      if (s.validCount >= 2) deltaMv.add(at, s.deltaMv);
      if (longDue) {
        avgCellLong.add(at, s.vAvg);
        if (s.validCount >= 2) deltaLong.add(at, s.deltaMv);
      }
    }
    return reset;
  }

  void _resetCells(int n) {
    _cellCount = n;
    _cellShort = List<Series>.generate(n, (_) => Series(shortCapacity));
    _cellLong = List<Series>.generate(n, (_) => Series(longCapacity));
    _cellDev = List<Series>.generate(n, (_) => Series(shortCapacity));
    _cellMax = List<CellExtreme?>.filled(n, null);
    _cellMin = List<CellExtreme?>.filled(n, null);
    avgCell.clear();
    avgCellLong.clear();
    deltaMv.clear();
    deltaLong.clear();
    _lastLongAt = null;
  }

  /// Xoá toàn bộ lịch sử (ví dụ khi người dùng bấm "Đặt lại phiên").
  void clear() {
    _resetCells(0);
    packVoltage.clear();
    packCurrent.clear();
  }

  bool _ok(int i) => i >= 0 && i < _cellCount;

  Series? cellSeries(int i, {bool longRange = false}) =>
      !_ok(i) ? null : (longRange ? _cellLong[i] : _cellShort[i]);

  CellExtreme? maxOf(int i) => _ok(i) ? _cellMax[i] : null;
  CellExtreme? minOf(int i) => _ok(i) ? _cellMin[i] : null;

  /// Độ lệch trung bình của cell so với TB pack nếu đã có đủ mẫu.
  CellTrend? trendOf(int i, int minSamples) {
    if (!_ok(i)) return null;
    final s = _cellDev[i];
    if (s.length < minSamples) return null;
    final vals = s.values();
    final n = vals.length < minSamples * 2 ? vals.length : minSamples * 2;
    var sum = 0.0;
    for (var k = vals.length - n; k < vals.length; k++) {
      sum += vals[k];
    }
    return CellTrend(i, sum / n, n);
  }

  List<CellTrend> trends(int minSamples) {
    final out = <CellTrend>[];
    for (var i = 0; i < _cellCount; i++) {
      final t = trendOf(i, minSamples);
      if (t != null) out.add(t);
    }
    return out;
  }
}
