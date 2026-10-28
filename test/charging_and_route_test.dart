import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mybike_app/core/services/charging_station_service.dart';
import 'package:mybike_app/core/services/energy_estimator.dart';
import 'package:mybike_app/core/services/route_service.dart';

void main() {
  group('ChargingStationService.parse', () {
    test('đọc node và way(center), bỏ phần tử thiếu tọa độ', () {
      final body = jsonEncode({
        'elements': [
          {'type': 'node', 'id': 1, 'lat': 10.1, 'lon': 106.1, 'tags': {'name': 'A', 'operator': 'X', 'socket:type2': '2'}},
          {'type': 'way', 'id': 2, 'center': {'lat': 10.2, 'lon': 106.2}, 'tags': {}},
          {'type': 'node', 'id': 3, 'tags': {'name': 'hỏng'}},
        ]
      });
      final r = ChargingStationService.parse(body);
      expect(r.length, 2);
      expect(r[0].name, 'A');
      expect(r[0].sockets, 'type2×2');
      expect(r[1].name, 'Trạm sạc');
      expect(r[1].id, 'way/2');
    });
    test('JSON không đúng dạng → rỗng', () {
      expect(ChargingStationService.parse('{"x":1}'), isEmpty);
    });
  });

  group('RouteService.parse', () {
    final body = jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 1500.0,
          'duration': 300.0,
          'geometry': {
            'coordinates': [
              [106.0, 10.0],
              [106.01, 10.0]
            ]
          },
          'legs': [
            {
              'steps': [
                {'distance': 800.0, 'name': 'Đường A', 'maneuver': {'type': 'depart', 'location': [106.0, 10.0]}},
                {'distance': 700.0, 'name': 'Đường B', 'maneuver': {'type': 'turn', 'modifier': 'left', 'location': [106.005, 10.0]}},
                {'distance': 0.0, 'name': '', 'maneuver': {'type': 'arrive', 'location': [106.01, 10.0]}},
              ]
            }
          ]
        }
      ]
    });
    test('đọc tuyến, điểm và các bước', () {
      final r = RouteService.parse(body)!;
      expect(r.points.length, 2);
      expect(r.distanceKm, 1.5);
      expect(r.steps.length, 3);
      expect(r.steps[1].instruction, 'Rẽ trái vào Đường B');
      expect(r.steps.last.instruction, 'Đến nơi');
    });
    test('mã lỗi → null', () {
      expect(RouteService.parse('{"code":"NoRoute","routes":[]}'), isNull);
    });
    test('URL dùng thứ tự lon,lat', () {
      final u = RouteService.buildUri([const LatLng(10, 106), const LatLng(11, 107)]);
      expect(u.path.contains('106.0,10.0;107.0,11.0'), isTrue);
    });
  });

  group('EnergyEstimator', () {
    test('dùng trung vị lịch sử, bỏ chuyến quá ngắn', () {
      final e = EnergyEstimator.estimate(history: const [
        TripSample(10, 10), // 1.0
        TripSample(20, 30), // 1.5
        TripSample(1, 1), // bỏ
        TripSample(10, 20), // 2.0
      ])!;
      expect(e.percentPerKm, 1.5);
      expect(e.fromHistory, isTrue);
      expect(e.samples, 3);
    });
    test('không có lịch sử → dùng số xe báo, có nhãn nguồn', () {
      final e = EnergyEstimator.estimate(history: const [], percent: 50, kmLeft: 100)!;
      expect(e.percentPerKm, 0.5);
      expect(e.fromHistory, isFalse);
      expect(e.basis.contains('xe báo'), isTrue);
    });
    test('không có dữ liệu nào → null (không bịa số)', () {
      expect(EnergyEstimator.estimate(history: const []), isNull);
    });
    test('pin đến nơi và tầm đi', () {
      expect(EnergyEstimator.batteryAfter(80, 20, 1.5), 50);
      expect(EnergyEstimator.rangeKm(80, 15, 1.5), closeTo(43.33, 0.01));
    });
  });

  group('ChargePlanner', () {
    // Tuyến thẳng ~ 0.01° kinh độ ≈ 1.1 km mỗi đoạn, 10 đoạn ≈ 11 km.
    final route = [for (var i = 0; i <= 10; i++) LatLng(10.0, 106.0 + i * 0.01)];
    ChargingStation st(String id, double lat, double lng) => ChargingStation(id: id, name: id, lat: lat, lng: lng);

    test('chọn trạm xa nhất mà vẫn tới được với pin ≥ dự phòng', () {
      final stations = [st('gần', 10.0, 106.02), st('xa', 10.0, 106.08), st('quáXa', 10.0, 106.10)];
      // 5 %/km: 106.08 ≈ 8.9 km → 80-44=36% OK; 106.10 ≈ 11.1 km → 80-55=25% cũng OK
      final s = ChargePlanner.pickStop(route: route, stations: stations, startPercent: 80, percentPerKm: 5, reservePercent: 30);
      expect(s!.station.id, 'xa'); // quáXa còn 25% < 30%
    });
    test('trạm lệch tuyến quá xa bị loại', () {
      final s = ChargePlanner.pickStop(
        route: route,
        stations: [st('lệch', 10.1, 106.05)], // ~11 km lệch
        startPercent: 90,
        percentPerKm: 1,
      );
      expect(s, isNull);
    });
    test('không trạm nào tới được → null', () {
      final s = ChargePlanner.pickStop(
        route: route,
        stations: [st('x', 10.0, 106.05)],
        startPercent: 20,
        percentPerKm: 5,
      );
      expect(s, isNull);
    });
    test('needsCharging', () {
      expect(ChargePlanner.needsCharging(startPercent: 50, totalKm: 40, percentPerKm: 1.5), isTrue); // 50-60<15
      expect(ChargePlanner.needsCharging(startPercent: 90, totalKm: 20, percentPerKm: 1.5), isFalse);
    });
  });
}
