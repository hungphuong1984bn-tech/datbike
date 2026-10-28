import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/config/cluster_config.dart';
import 'package:mybike_app/core/models/trip_gps_point.dart';
import 'package:mybike_app/core/services/gpx_exporter.dart';
import 'package:mybike_app/features/cluster/cluster_screen.dart';

void main() {
  group('ClusterConfig', () {
    test('mặc định: Portrait cố định, không cho xoay', () {
      expect(ClusterConfig.defaults.allowRotate, isFalse);
    });

    test('encode/decode giữ nguyên cấu hình', () {
      final c = ClusterConfig.defaults.copyWith(
        theme: ClusterTheme.touring,
        hidden: {ClusterMetric.odo},
        fontScale: 1.2,
        speedSource: SpeedSource.gps,
        allowRotate: true,
        accent: 0xFF14B8A6,
      );
      final d = ClusterConfig.decode(c.encode());
      expect(d.theme, ClusterTheme.touring);
      expect(d.hidden, {ClusterMetric.odo});
      expect(d.fontScale, 1.2);
      expect(d.speedSource, SpeedSource.gps);
      expect(d.allowRotate, isTrue);
      expect(d.accent, 0xFF14B8A6);
    });

    test('dữ liệu hỏng → mặc định, không ném lỗi', () {
      expect(ClusterConfig.decode('{không phải json').theme, ClusterConfig.defaults.theme);
      expect(ClusterConfig.decode(null).allowRotate, isFalse);
      expect(ClusterConfig.decode('{"theme":"xyz","order":["lạ","odo"]}').order.length,
          ClusterMetric.values.length);
    });

    test('visible tôn trọng thứ tự và ẩn', () {
      final c = ClusterConfig.defaults.copyWith(
        order: [ClusterMetric.battery, ClusterMetric.speed, ...ClusterMetric.values.where((m) => m != ClusterMetric.battery && m != ClusterMetric.speed)],
        hidden: {ClusterMetric.voltage},
      );
      expect(c.visible.first, ClusterMetric.battery);
      expect(c.visible.contains(ClusterMetric.voltage), isFalse);
    });
  });

  group('pickSpeed', () {
    test('ưu tiên nguồn đã chọn', () {
      final r = pickSpeed(preferred: SpeedSource.ble, bleKmh: 40, gpsKmh: 38);
      expect(r.value, 40);
      expect(r.label, 'XE (BLE)');
    });
    test('nguồn chính mất → dự phòng có gắn nhãn', () {
      final r = pickSpeed(preferred: SpeedSource.ble, bleKmh: null, gpsKmh: 38);
      expect(r.value, 38);
      expect(r.label.contains('dự phòng'), isTrue);
    });
    test('không nguồn nào → null', () {
      expect(pickSpeed(preferred: SpeedSource.gps, bleKmh: null, gpsKmh: null).value, isNull);
    });
  });

  group('GPX', () {
    test('không có điểm → null', () {
      expect(GpxExporter.build(name: 'x', points: const []), isNull);
    });
    test('có điểm → GPX hợp lệ cơ bản, escape tên', () {
      final xml = GpxExporter.build(name: 'A&B', points: [
        TripGpsPoint(lat: 10.5, lng: 106.5, speedKmh: 20, timestamp: DateTime.utc(2026, 10, 28, 1, 2, 3), altitude: 5),
      ])!;
      expect(xml.contains('<trkpt lat="10.500000" lon="106.500000">'), isTrue);
      expect(xml.contains('A&amp;B'), isTrue);
      expect(xml.contains('2026-10-28T01:02:03.000Z'), isTrue);
    });
  });
}
