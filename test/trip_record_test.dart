import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_controller.dart';

void main() {
  group('TripRecord serialization and calculation tests', () {
    test('TripRecord toJson and fromJson preserve all fields', () {
      final now = DateTime.now();
      final record = TripRecord(
        startTime: now.subtract(const Duration(minutes: 25)),
        endTime: now,
        distanceKm: 14.85,
        durationSec: 1500,
        avgSpeedKmh: 35.6,
        maxSpeedKmh: 68.2,
        usedPercent: 12,
        startOdo: 120.5,
        endOdo: 135.35,
      );

      final json = record.toJson();
      final restored = TripRecord.fromJson(json);

      expect(restored.distanceKm, 14.85);
      expect(restored.durationSec, 1500);
      expect(restored.avgSpeedKmh, 35.6);
      expect(restored.maxSpeedKmh, 68.2);
      expect(restored.usedPercent, 12);
      expect(restored.startOdo, 120.5);
      expect(restored.endOdo, 135.35);
    });

    test('TripRecord handles empty / missing JSON keys gracefully', () {
      final restored = TripRecord.fromJson(const {});
      expect(restored.distanceKm, 0.0);
      expect(restored.durationSec, 0);
      expect(restored.avgSpeedKmh, 0.0);
      expect(restored.maxSpeedKmh, 0.0);
      expect(restored.usedPercent, 0);
      expect(restored.startOdo, isNull);
      expect(restored.endOdo, isNull);
    });
  });
}
