import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/telemetry/ops_history.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 8);
  bool add(OpsHistory h, int sec,
          {double v = 80, double a = -10, double bms = 30, double ecu = 0}) =>
      h.add(
        at: t0.add(Duration(seconds: sec)),
        speedKmh: 20,
        voltageV: v,
        phaseAmps: a,
        bmsC: bms,
        ecuC: ecu,
        motorC: 0,
      );

  test('chỉ ghi mẫu khi đủ khoảng cách thời gian', () {
    final h = OpsHistory();
    expect(add(h, 0), true);
    expect(add(h, 1), false);
    expect(add(h, 2), true);
    expect(h.speed.length, 2);
  });

  test('công suất = V × |A|; nhiệt độ 0 không vào biểu đồ', () {
    final h = OpsHistory();
    add(h, 0);
    expect(h.powerW.last, 800);
    expect(h.bmsTemp.length, 1);
    expect(h.ecuTemp.length, 0);
    expect(h.motorTemp.length, 0);
  });

  test('điện áp 0 không tạo điểm điện áp/công suất', () {
    final h = OpsHistory();
    add(h, 0, v: 0);
    expect(h.voltage.length, 0);
    expect(h.powerW.length, 0);
    expect(h.speed.length, 1);
  });

  test('thống kê min/avg/max', () {
    final s = SeriesStats.of([1, 2, 3])!;
    expect(s.min, 1);
    expect(s.avg, 2);
    expect(s.max, 3);
    expect(SeriesStats.of([]), null);
  });
}
