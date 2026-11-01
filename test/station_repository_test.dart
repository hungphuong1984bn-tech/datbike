import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mybike_app/core/charging/station_repository.dart';
import 'package:mybike_app/core/services/charging_station_service.dart';

const _osmOk = '{"elements":[{"type":"node","id":1,"lat":21.0,"lon":105.8,"tags":{"name":"Trạm A","amenity":"charging_station"}}]}';
const _seedJson =
    '{"stations":[{"id":"datbike/x","name":"Dat Bike X","lat":21.04831,"lng":105.881862,"category":"datBike","status":"unverified"},'
    '{"id":"bad","name":"Thiếu tọa độ"}]}';

Future<List<ChargingStation>> _seed() async => StationRepository.parseSeed(_seedJson);

Future<StationResult> _run(http.Client c) => StationRepository.fetchNear(
      21.0,
      105.8,
      client: c,
      endpoints: const ['http://a/x', 'http://b/x'],
      timeout: const Duration(milliseconds: 200),
      delay: Duration.zero,
      seedLoader: _seed,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parseSeed bỏ bản ghi thiếu tọa độ, không tự tạo trạm', () {
    final l = StationRepository.parseSeed(_seedJson);
    expect(l.length, 1);
    expect(l.single.category, StationCategory.datBike);
    expect(l.single.chargingConfirmed, false);
    expect(StationRepository.parseSeed('không phải json'), isEmpty);
  });

  test('máy chủ hoạt động: gộp seed + OSM, lưu cache', () async {
    final r = await _run(MockClient((_) async => http.Response(_osmOk, 200)));
    expect(r.error, isNull);
    expect(r.stations.length, 2);
    expect(r.sources, contains('OpenStreetMap'));
    expect(await StationRepository.loadCache(), isNotNull);
  });

  test('404 / 500 / 429: vẫn còn dữ liệu đóng gói, phân loại lỗi đúng', () async {
    for (final (code, kind) in [
      (404, StationFetchError.notFound),
      (500, StationFetchError.serverError),
      (429, StationFetchError.rateLimited),
    ]) {
      final r = await _run(MockClient((_) async => http.Response('x', code)));
      expect(r.errorKind, kind, reason: '$code');
      expect(r.stations.map((e) => e.id), contains('datbike/x'));
    }
  });

  test('timeout: không treo, báo lỗi timeout', () async {
    final r = await _run(MockClient((_) => Completer<http.Response>().future));
    expect(r.errorKind, StationFetchError.timeout);
    expect(r.stations, isNotEmpty);
  });

  test('retry có giới hạn và chuyển sang máy chủ dự phòng', () async {
    final hits = <String>[];
    final r = await _run(MockClient((req) async {
      hits.add(req.url.host);
      return req.url.host == 'a' ? http.Response('', 503) : http.Response(_osmOk, 200);
    }));
    expect(hits, ['a', 'b']);
    expect(r.error, isNull);

    hits.clear();
    await _run(MockClient((req) async {
      hits.add(req.url.host);
      return http.Response('', 500);
    }));
    expect(hits.length, StationRepository.maxAttempts);
  });

  test('mất Internet: dùng cache đã lưu + seed', () async {
    await _run(MockClient((_) async => http.Response(_osmOk, 200)));
    final r = await _run(MockClient((_) async => throw const SocketException('offline')));
    expect(r.fromCache, true);
    expect(r.errorKind, StationFetchError.noInternet);
    expect(r.stations.length, 2);
  });

  test('JSON hỏng không làm app lỗi', () async {
    final r = await _run(MockClient((_) async => http.Response('<html>', 200)));
    expect(r.errorKind, StationFetchError.badData);
    expect(r.stations, isNotEmpty);
  });

  test('không nhân đôi: cùng id hoặc <40 m cùng tên', () {
    const a = ChargingStation(id: '1', name: 'Dat Bike X', lat: 21.0, lng: 105.8, category: StationCategory.datBike);
    const b = ChargingStation(id: '2', name: 'dat bike x', lat: 21.00001, lng: 105.8, phone: '0123');
    const c = ChargingStation(id: '3', name: 'Dat Bike X', lat: 21.01, lng: 105.8);
    final out = StationDedupe.dedupe([b, a, c]);
    expect(out.length, 2);
    final kept = out.firstWhere((e) => e.id == '1');
    expect(kept.category, StationCategory.datBike);
    expect(kept.phone, '0123'); // bổ sung trường thiếu, không đổi loại
  });

  test('cache nhiều vùng + chuyển cache v2 cũ', () async {
    SharedPreferences.setMockInitialValues({
      'charge_stations_cache_v2': jsonEncode({
        'lat': 10.0,
        'lng': 106.0,
        'at': '2026-10-01T00:00:00',
        'stations': [
          {'id': 'old', 'name': 'Cũ', 'lat': 10.0, 'lng': 106.0}
        ],
      }),
    });
    await StationRepository.saveRegion(21.0, 105.8, [
      const ChargingStation(id: 'new', name: 'Mới', lat: 21.0, lng: 105.8),
    ]);
    final c = await StationRepository.loadCache();
    expect(c!.stations.map((e) => e.id).toSet(), {'old', 'new'});
  });

  test('model: category/chargingConfirmed round-trip, bản cũ mặc định cộng đồng', () {
    const s = ChargingStation(id: 'a', name: 'A', lat: 1, lng: 2, category: StationCategory.datBike);
    final back = ChargingStation.fromJson(s.toJson());
    expect(back.category, StationCategory.datBike);
    expect(back.chargingConfirmed, false);
    final old = ChargingStation.fromJson({'id': 'b', 'name': 'B', 'lat': 1, 'lng': 2});
    expect(old.category, StationCategory.community);
  });
}
