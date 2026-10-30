import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mybike_app/core/charging/place_search_service.dart';
import 'package:mybike_app/core/charging/station_search.dart';
import 'package:mybike_app/core/charging/station_user_store.dart';
import 'package:mybike_app/core/services/charging_station_service.dart';
import 'package:mybike_app/core/services/energy_estimator.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChargingStation st(
  String id,
  double lat,
  double lng, {
  VehicleSupport v = VehicleSupport.motorbike,
  StationStatus status = StationStatus.unverified,
  double? kw,
  String? sockets,
  String? hours,
  String name = 'Trạm',
}) =>
    ChargingStation(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      vehicle: v,
      status: status,
      powerKw: kw,
      sockets: sockets,
      openingHours: hours,
    );

void main() {
  const origin = LatLng(21.0, 105.0);

  group('Phân tích dữ liệu OSM', () {
    test('chỉ lấy loại xe từ thẻ, không suy từ tên', () {
      const body = '''{"elements":[
        {"type":"node","id":1,"lat":21.0,"lon":105.0,"tags":{"name":"Trạm xe máy điện ABC"}},
        {"type":"node","id":2,"lat":21.0,"lon":105.0,"tags":{"motorcycle":"yes","socket:type2":"2","socket:type2:output":"7.4 kW","capacity":"2"}},
        {"type":"node","id":3,"lat":21.0,"lon":105.0,"tags":{"motorcar":"yes"}},
        {"type":"node","id":4,"lat":21.0,"lon":105.0,"tags":{"opening_hours":"off"}}
      ]}''';
      final l = ChargingStationService.parse(body);
      expect(l[0].vehicle, VehicleSupport.unknown); // tên "xe máy điện" KHÔNG đủ căn cứ
      expect(l[1].vehicle, VehicleSupport.motorbike);
      expect(l[1].powerKw, 7.4);
      expect(l[1].ports, 2);
      expect(l[2].vehicle, VehicleSupport.car);
      expect(l[3].status, StationStatus.closed);
      expect(l[0].status, StationStatus.unverified);
      expect(l[0].powerKw, isNull);
      expect(l[0].fee, isNull);
    });

    test('JSON khứ hồi giữ nguyên trường', () {
      final s = st('x', 1, 2, v: VehicleSupport.both, kw: 22, sockets: 'type2×1');
      final r = ChargingStation.fromJson(s.toJson());
      expect(r.vehicle, VehicleSupport.both);
      expect(r.powerKw, 22);
      expect(r.status, StationStatus.unverified);
    });

    test('Nominatim parse', () {
      final l = PlaceSearchService.parse('[{"lat":"21.03","lon":"105.85","display_name":"Hà Nội, Việt Nam"}]');
      expect(l.single.name, 'Hà Nội, Việt Nam');
      expect(PlaceSearchService.parse('{}'), isEmpty);
    });
  });

  group('Bộ lọc', () {
    final all = [
      st('near', 21.01, 105.0, name: 'Gần'),
      st('far', 21.3, 105.0, name: 'Xa'),
      st('car', 21.005, 105.0, v: VehicleSupport.car, name: 'Ô tô'),
      st('unk', 21.006, 105.0, v: VehicleSupport.unknown, name: 'Chưa rõ'),
      st('closed', 21.007, 105.0, status: StationStatus.closed, name: 'Đóng'),
    ];

    test('mặc định ẩn trạm ô tô và trạm đã đóng; xe máy xếp trước', () {
      final r = StationSearch.apply(all, const StationFilter(radiusKm: 50), origin: origin);
      final ids = r.map((e) => e.station.id).toList();
      expect(ids, ['near', 'far', 'unk']);
      expect(ids.contains('car'), isFalse);
    });

    test('bán kính 5 km loại trạm xa', () {
      final r = StationSearch.apply(all, const StationFilter(radiusKm: 5), origin: origin);
      expect(r.map((e) => e.station.id), isNot(contains('far')));
    });

    test('lọc công suất loại trạm không có dữ liệu', () {
      final l = [st('a', 21, 105, kw: 22), st('b', 21, 105)];
      final r = StationSearch.apply(l, const StationFilter(radiusKm: null, minPowerKw: 7), origin: origin);
      expect(r.map((e) => e.station.id), ['a']);
    });

    test('lọc 24/7 và chuẩn đầu nối', () {
      final l = [
        st('a', 21, 105, hours: '24/7', sockets: 'type2×2'),
        st('b', 21, 105, hours: 'Mo-Fr 08:00-17:00', sockets: 'chademo×1'),
      ];
      expect(StationSearch.apply(l, const StationFilter(radiusKm: null, only24h: true), origin: origin).length, 1);
      expect(StationSearch.apply(l, const StationFilter(radiusKm: null, connector: 'chademo'), origin: origin).single.station.id, 'b');
      expect(StationSearch.availableConnectors(l), ['chademo', 'type2']);
    });

    test('tìm theo từ khóa tên/địa chỉ', () {
      final l = [
        const ChargingStation(id: '1', name: 'VinFast Cầu Giấy', lat: 21, lng: 105, address: 'Hà Nội'),
        const ChargingStation(id: '2', name: 'Khác', lat: 21, lng: 105, address: 'Đà Nẵng'),
      ];
      final r = StationSearch.apply(l, const StationFilter(radiusKm: null, query: 'hà nội', includeUnknownVehicle: true), origin: origin);
      expect(r.single.station.id, '1');
    });
  });

  group('Khả năng tới trạm', () {
    const cons = ConsumptionEstimate(1.0, 'thử nghiệm', true, 5);

    test('không có % pin trực tiếp → không ước tính', () {
      final a = ReachEstimator.assess(straightKm: 3, percent: null, consumption: cons);
      expect(a.level, ReachLevel.unknown);
      expect(a.batteryAtArrival, isNull);
    });

    test('không có tiêu hao → không ước tính', () {
      expect(ReachEstimator.assess(straightKm: 3, percent: 80).level, ReachLevel.unknown);
    });

    test('các mức (chim bay × 1,3; dự phòng 15%)', () {
      // 80% − 1%/km × (km × 1,3)
      expect(ReachEstimator.assess(straightKm: 10, percent: 80, consumption: cons).level, ReachLevel.likely); // 67%
      expect(ReachEstimator.assess(straightKm: 45, percent: 80, consumption: cons).level, ReachLevel.tight); // ~21,5%
      expect(ReachEstimator.assess(straightKm: 55, percent: 80, consumption: cons).level, ReachLevel.risky); // ~8,5%
      expect(ReachEstimator.assess(straightKm: 70, percent: 80, consumption: cons).level, ReachLevel.unlikely); // −11%
    });

    test('dùng quãng tuyến thật khi có', () {
      final a = ReachEstimator.assess(straightKm: 10, routeKm: 20, percent: 50, consumption: cons);
      expect(a.batteryAtArrival, 30);
    });
  });

  group('Dữ liệu cục bộ', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('yêu thích bật/tắt và còn nguyên sau khi đọc lại', () async {
      final s = st('fav', 21, 105, name: 'Yêu thích');
      expect(await StationUserStore.toggleFavorite(s), isTrue);
      expect((await StationUserStore.favorites()).single.name, 'Yêu thích');
      expect(await StationUserStore.toggleFavorite(s), isFalse);
      expect(await StationUserStore.favorites(), isEmpty);
    });

    test('lịch sử không trùng, mới nhất trước', () async {
      await StationUserStore.addHistory('Hà Nội');
      await StationUserStore.addHistory('Huế');
      await StationUserStore.addHistory('hà nội');
      expect(await StationUserStore.history(), ['hà nội', 'Huế']);
    });

    test('báo cáo luôn là chưa xác minh', () async {
      final r = StationReport(
        stationId: 'x',
        stationName: 'X',
        kind: ReportKind.closed,
        note: '',
        at: DateTime(2026, 10, 30),
      );
      await StationUserStore.addReport(r);
      final l = await StationUserStore.reports();
      expect(l.single.verified, isFalse);
      expect(l.single.kind, ReportKind.closed);
    });
  });
}
