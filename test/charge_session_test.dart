import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/charging/charge_session.dart';

void feed(ChargeTracker t, DateTime t0, int fromSec, int toSec,
    {double w = 1000, double soc = 50, double step = 0, bool charging = true}) {
  for (var s = fromSec; s <= toSec; s++) {
    t.onSample(
      at: t0.add(Duration(seconds: s)),
      charging: charging,
      powerW: w,
      voltage: 80,
      currentA: w / 80,
      soc: soc + step * s,
    );
  }
}

void main() {
  final t0 = DateTime(2026, 1, 1, 8);

  test('tích phân năng lượng: 1000 W trong 3600 s ≈ 1000 Wh', () {
    final t = ChargeTracker();
    feed(t, t0, 0, 3600);
    expect(t.ongoing!.energyWh, closeTo(1000, 0.5));
  });

  test('đoạn mất dữ liệu dài không được cộng bù năng lượng', () {
    final t = ChargeTracker();
    feed(t, t0, 0, 60);
    feed(t, t0, 360, 420); // mất 300 s
    expect(t.ongoing!.gapSeconds, greaterThan(250));
    expect(t.ongoing!.energyWh, closeTo(2000 * 60 / 3600 * 1.0, 1.0));
  });

  test('ngừng sạc lâu hơn ngưỡng thì đóng phiên và lưu lịch sử', () {
    final t = ChargeTracker();
    feed(t, t0, 0, 120);
    feed(t, t0, 121, 150, charging: false, w: 0);
    expect(t.ongoing, isNull);
    expect(t.history.length, 1);
    expect(t.history.first.durationUntil(t0), isNotNull);
  });

  test('phiên quá ngắn không được ghi vào lịch sử', () {
    final t = ChargeTracker();
    feed(t, t0, 0, 20);
    feed(t, t0, 21, 60, charging: false, w: 0);
    expect(t.history, isEmpty);
  });

  test('ETA: ưu tiên bộ sạc báo; thiếu dữ liệu thì null (không đoán)', () {
    final t = ChargeTracker();
    feed(t, t0, 0, 30, soc: 50);
    expect(t.eta(chargerEtaSec: 0, currentSoc: 50), isNull);
    final e = t.eta(chargerEtaSec: 1800, currentSoc: 50)!;
    expect(e.source, EtaSource.charger);
    expect(e.remaining.inMinutes, 30);
  });

  test('ETA theo tốc độ đo: 1% / 60 s, còn 40% → ~40 phút', () {
    final t = ChargeTracker();
    feed(t, t0, 0, 300, soc: 50, step: 1 / 60);
    final e = t.eta(chargerEtaSec: 0, currentSoc: 55)!;
    expect(e.source, EtaSource.measuredRate);
    expect(e.remaining.inMinutes, closeTo(45, 1));
  });

  test('JSON khứ hồi giữ nguyên số liệu', () {
    final s = ChargeSession(
        start: t0, end: t0.add(const Duration(hours: 1)), startSoc: 20,
        endSoc: 80, energyWh: 4200, peakPowerW: 1500, peakCurrentA: 20);
    final r = ChargeSession.fromJson(s.toJson())!;
    expect(r.energyWh, 4200);
    expect(r.socGain, 60);
    expect(ChargeSession.fromJson('rác'), isNull);
  });
}
