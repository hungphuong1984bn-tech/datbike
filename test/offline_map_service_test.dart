import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mybike_app/core/services/offline_map_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineMapService Coordinate and Region Tests', () {
    test('lon2tileX and lat2tileY convert geographic coordinates correctly', () {
      // Tọa độ Hồ Gươm (Hà Nội): 21.0285, 105.8542 tại Zoom 14
      final xHanoi = OfflineMapService.lon2tileX(105.8542, 14);
      final yHanoi = OfflineMapService.lat2tileY(21.0285, 14);

      expect(xHanoi, greaterThan(0));
      expect(yHanoi, greaterThan(0));
      expect(xHanoi, equals(13009));
      expect(yHanoi, equals(7212));
    });

    test('createRadiusBounds produces valid bounding box', () {
      const center = LatLng(10.7719, 106.7195);
      final bounds = OfflineMapService.createRadiusBounds(center, 5.0);

      expect(bounds.north, greaterThan(center.latitude));
      expect(bounds.south, lessThan(center.latitude));
      expect(bounds.east, greaterThan(center.longitude));
      expect(bounds.west, lessThan(center.longitude));
    });

    test('calculateTileList computes accurate non-empty tile list for presets', () {
      final presets = OfflineMapService.getPresets();
      expect(presets, isNotEmpty);

      final hcm = presets.first;
      final tiles = OfflineMapService.instance.calculateTileList(
        bounds: hcm.bounds,
        minZoom: 13,
        maxZoom: 14,
      );

      expect(tiles, isNotEmpty);
      for (final t in tiles) {
        expect(t.z, isIn([13, 14]));
        expect(t.x, greaterThan(0));
        expect(t.y, greaterThan(0));
      }
    });

    test('DownloadProgress calculates progress percentage and formatted size', () {
      const progress = DownloadProgress(
        current: 50,
        total: 100,
        bytes: 5 * 1024 * 1024,
        isRunning: true,
      );

      expect(progress.percent, equals(0.5));
      expect(progress.sizeMbText, equals('5.0 MB'));
    });
  });
}
