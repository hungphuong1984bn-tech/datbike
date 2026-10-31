// Test trường dữ liệu có metadata — Unit Test.

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/data_field.dart';
import 'package:mybike_app/core/proto/bike_log.dart';

final _t0 = DateTime(2026, 10, 31, 12);
const _w = Duration(seconds: 4);

void main() {
  group('DataField.freshness', () {
    test('chưa có giá trị → none', () {
      const f = DataField<double>.missing(unit: 'V', source: FieldSource.bleDashboard);
      expect(f.freshness(_t0, _w), Freshness.none);
      expect(f.isLive(_t0, _w), isFalse);
      expect(f.liveValue(_t0, _w), isNull);
    });
    test('trong cửa sổ → live; ngoài cửa sổ → stale', () {
      final f = DataField<double>(
          value: 50, unit: '%', source: FieldSource.bleDashboard, receivedAt: _t0);
      expect(f.freshness(_t0.add(const Duration(seconds: 4)), _w), Freshness.live);
      expect(f.freshness(_t0.add(const Duration(seconds: 5)), _w), Freshness.stale);
      expect(f.liveValue(_t0.add(const Duration(seconds: 5)), _w), isNull);
    });
    test('nguồn cache KHÔNG BAO GIỜ là live dù vừa nhận', () {
      final f = DataField<double>(
          value: 50, unit: '%', source: FieldSource.cache, receivedAt: _t0);
      expect(f.freshness(_t0, _w), Freshness.cached);
      expect(f.isLive(_t0, _w), isFalse);
    });
    test('giá trị không hợp lệ không bao giờ là live', () {
      final f = DataField<double>(
          value: 0,
          unit: 'V',
          source: FieldSource.bleDashboard,
          receivedAt: _t0,
          valid: false);
      expect(f.freshness(_t0, _w), Freshness.live);
      expect(f.isLive(_t0, _w), isFalse);
    });
    test('toJson có đủ metadata', () {
      final f = DataField<double>(
          value: 48.2, unit: 'V', source: FieldSource.bleBatteryLog, receivedAt: _t0);
      final j = f.toJson(_t0, _w);
      expect(j['unit'], 'V');
      expect(j['source'], 'bleBatteryLog');
      expect(j['freshness'], 'live');
      expect(j['valid'], true);
    });
  });

  group('TelemetryFields.fromBike', () {
    test('đơn vị và nguồn đúng', () {
      final m = BikeLogMsg()
        ..speed = 30
        ..voltage = 72.1
        ..percent = 80
        ..phase = 12.5
        ..ecu = 40
        ..motor = 45
        ..bmsTemp = 33
        ..odo = 1234.5
        ..kmLeft = 60;
      final t = TelemetryFields.fromBike(m, _t0);
      expect(t.speed.unit, 'km/h');
      expect(t.packVoltage.unit, 'V');
      expect(t.packPercent.unit, '%');
      expect(t.phaseCurrent.unit, 'A');
      expect(t.ecuTemp.unit, '°C');
      expect(t.odometer.unit, 'km');
      for (final e in t.entries) {
        expect(e.value.source, FieldSource.bleDashboard);
        expect(e.value.receivedAt, _t0);
        expect(e.value.valid, isTrue, reason: e.key);
      }
    });
    test('giá trị 0 của điện áp/nhiệt độ bị đánh dấu không hợp lệ, tốc độ 0 vẫn hợp lệ', () {
      final t = TelemetryFields.fromBike(BikeLogMsg(), _t0);
      expect(t.packVoltage.valid, isFalse);
      expect(t.packVoltage.invalidReason, isNotNull);
      expect(t.ecuTemp.valid, isFalse);
      expect(t.speed.valid, isTrue);
      expect(t.packPercent.valid, isTrue);
    });
    test('SOC ngoài 0–100 không hợp lệ', () {
      final m = BikeLogMsg()..percent = 130;
      expect(TelemetryFields.fromBike(m, _t0).packPercent.valid, isFalse);
    });
    test('truyền nguồn cache thì mọi trường là cached', () {
      final t = TelemetryFields.fromBike(BikeLogMsg()..voltage = 70, _t0,
          source: FieldSource.cache);
      expect(t.packVoltage.freshness(_t0, _w), Freshness.cached);
    });
    test('empty: mọi trường none', () {
      for (final e in TelemetryFields.empty.entries) {
        expect(e.value.freshness(_t0, _w), Freshness.none, reason: e.key);
      }
    });
  });

  group('BatteryFields.fromMsg', () {
    test('có cell: max/min/delta tính đúng, delta là nguồn derived', () {
      final m = BatteryLogMsg()
        ..voltage = 72
        ..current = -3.5
        ..cellVols = [3.60, 3.62, 3.58];
      final b = BatteryFields.fromMsg(m, _t0);
      expect(b.cellCount.value, 3);
      expect(b.cellMaxV.value, closeTo(3.62, 1e-9));
      expect(b.cellMinV.value, closeTo(3.58, 1e-9));
      expect(b.deltaMv.value, closeTo(40, 1e-6));
      expect(b.deltaMv.source, FieldSource.derived);
      expect(b.packCurrent.valid, isTrue);
    });
    test('không có cell: không bịa số cell', () {
      final b = BatteryFields.fromMsg(BatteryLogMsg()..voltage = 72, _t0);
      expect(b.cellMaxV.hasValue, isFalse);
      expect(b.cellMaxV.valid, isFalse);
      expect(b.deltaMv.hasValue, isFalse);
      expect(b.cellCount.valid, isFalse);
    });
    test('chênh lệch 0 mV vẫn hợp lệ', () {
      final m = BatteryLogMsg()..cellVols = [3.6, 3.6];
      expect(BatteryFields.fromMsg(m, _t0).deltaMv.valid, isTrue);
    });
    test('điện áp pack 0 không hợp lệ', () {
      final b = BatteryFields.fromMsg(BatteryLogMsg()..cellVols = [3.6], _t0);
      expect(b.packVoltage.valid, isFalse);
    });
  });
}
