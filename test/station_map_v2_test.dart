import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mybike_app/core/charging/external_nav.dart';
import 'package:mybike_app/core/charging/station_admin_store.dart';
import 'package:mybike_app/core/charging/station_analytics.dart';
import 'package:mybike_app/core/charging/station_cluster.dart';
import 'package:mybike_app/core/charging/station_log.dart';
import 'package:mybike_app/core/charging/station_marker_status.dart';
import 'package:mybike_app/core/charging/station_proposal_store.dart';
import 'package:mybike_app/core/charging/station_sync.dart';
import 'package:mybike_app/core/services/charging_station_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChargingStation st(String id, double lat, double lng, {StationStatus s = StationStatus.unverified}) =>
    ChargingStation(id: id, name: 'Trạm $id', lat: lat, lng: lng, status: s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StationLogStore.resetForTest();
    StationAdminAuth.debugSet(admin: false);
  });

  group('cluster', () {
    final items = [
      for (var i = 0; i < 10; i++) ClusterItem<int>(i, 21.0 + i * 0.0001, 105.0 + i * 0.0001),
      const ClusterItem<int>(99, 10.0, 106.0),
    ];
    test('zoom thấp gom nhóm, zoom cao tách riêng', () {
      final lo = StationClusterer.cluster<int>(items, zoom: 10);
      expect(lo.length, 2);
      expect(lo.firstWhere((c) => c.count > 1).count, 10);
      final hi = StationClusterer.cluster<int>(items, zoom: 17);
      expect(hi.length, 11);
    });
    test('lọc theo vùng nhìn thấy và phần tử ghim luôn hiện', () {
      const box = GeoBox(20.9, 104.9, 21.1, 105.1);
      final out = StationClusterer.cluster<int>(items, zoom: 17, box: box);
      expect(out.length, 10);
      final pinned = [...items, const ClusterItem<int>(5, 0, 0, pinned: true)];
      expect(StationClusterer.cluster<int>(pinned, zoom: 17, box: box).length, 11);
    });
  });

  test('trạng thái Marker: không tự coi là hoạt động', () {
    expect(markerStatusOf(st('a', 1, 1)), MarkerStatus.unverified);
    expect(markerStatusOf(st('a', 1, 1, s: StationStatus.active)), MarkerStatus.active);
    expect(markerStatusOf(st('a', 1, 1, s: StationStatus.closed)), MarkerStatus.paused);
    expect(markerStatusOf(st('a', 1, 1, s: StationStatus.active), isUpdating: true), MarkerStatus.updating);
    expect(markerStatusOf(st('a', 1, 1, s: StationStatus.active), isUpdating: true, hasWarning: true), MarkerStatus.warning);
  });

  group('log', () {
    test('không ghi tọa độ khi chưa đồng ý; làm tròn khi đồng ý', () async {
      await StationLogStore.record(StationEvent.search, query: '  Hà Nội ', areaLat: 21.04831, areaLng: 105.881862);
      var l = await StationLogStore.all();
      expect(l.single.areaLat, isNull);
      expect(l.single.query, 'Hà Nội');
      await StationLogConsent.setArea(true);
      await StationLogStore.record(StationEvent.view, stationId: 'x', areaLat: 21.04831, areaLng: 105.881862);
      l = await StationLogStore.all();
      expect(l.last.areaLat, 21.05);
      expect(l.last.areaLng, 105.88);
    });
    test('JSON khứ hồi, bỏ bản ghi hỏng', () {
      final a = StationActivityLog(event: StationEvent.navigate, at: DateTime(2026, 1, 2), anonId: 'u', stationId: 's', distanceKm: 1.234);
      final b = StationActivityLog.fromJson(a.toJson())!;
      expect(b.event, StationEvent.navigate);
      expect(b.stationId, 's');
      expect(StationActivityLog.fromJson({'e': 'khong-co', 't': 'x'}), isNull);
    });
    test('giới hạn số bản ghi', () async {
      for (var i = 0; i < StationLogStore.maxEntries + 5; i++) {
        await StationLogStore.record(StationEvent.filter);
      }
      expect((await StationLogStore.all()).length, StationLogStore.maxEntries);
    });
  });

  group('analytics', () {
    final now = DateTime(2026, 11, 3, 12);
    StationActivityLog log(StationEvent e, {String? sid, String? q, double? la, double? ln, String? d, Duration ago = const Duration(hours: 1)}) =>
        StationActivityLog(event: e, at: now.subtract(ago), anonId: 'u1', stationId: sid, query: q, areaLat: la, areaLng: ln, detail: d);

    test('rỗng khi chưa có log (không dữ liệu giả)', () {
      final a = StationAnalytics.compute(const [], [st('a', 21, 105)], now: now);
      expect(a.isEmpty, true);
      expect(a.heat, isEmpty);
      expect(a.top, isEmpty);
    });
    test('đếm, xếp hạng, heatmap và khu vực chưa có trạm', () {
      final logs = [
        log(StationEvent.view, sid: 'a'),
        log(StationEvent.view, sid: 'a'),
        log(StationEvent.navigate, sid: 'a', la: 21.0, ln: 105.0),
        log(StationEvent.navigateResult, sid: 'a', d: 'fail'),
        log(StationEvent.search, q: 'Hà  Nội', la: 10.0, ln: 106.0),
        log(StationEvent.emptyResult, la: 10.0, ln: 106.0),
        log(StationEvent.mapError),
        log(StationEvent.view, sid: 'a', ago: const Duration(days: 40)),
      ];
      final a = StationAnalytics.compute(logs, [st('a', 21.0, 105.0)], now: now, period: AnalyticsPeriod.month);
      expect(a.views, 2);
      expect(a.navigates, 1);
      expect(a.navigateFailures, 1);
      expect(a.errors, 1);
      expect(a.top.first.stationId, 'a');
      expect(a.searches.first.term, 'hà nội');
      expect(a.heat.first.weight, 4); // search 1 + emptyResult 3
      expect(a.uncovered.length, 1);
      expect(a.uncovered.first.lat, 10.0);
      expect(a.series.length, 30);
      expect(a.series.fold<int>(0, (x, y) => x + y), a.totalEvents);
    });
    test('thống kê số trạm', () {
      final c = StationCounts.from([st('a', 1, 1, s: StationStatus.active), st('b', 1, 1), st('c', 1, 1, s: StationStatus.paused)], pendingProposals: 2);
      expect((c.total, c.verified, c.unverified, c.paused, c.pendingProposals), (3, 1, 1, 1, 2));
    });
  });

  group('quản trị', () {
    ManagedStation draft(String id, {double lat = 21.0, double lng = 105.0}) => ManagedStation(
          id: id, code: 'THB-000001', name: 'Trạm thử', address: '1 Phố Huế, Hà Nội', lat: lat, lng: lng,
          createdBy: 't', createdAt: DateTime(2026), updatedAt: DateTime(2026));

    test('từ chối ghi khi chưa là admin', () async {
      expect(() => StationAdminStore.save(draft('thb/1')), throwsStateError);
    });
    test('thêm, sửa (ghi diff), xác minh, ẩn, xóa và xuất', () async {
      StationAdminAuth.debugSet(admin: true, name: 'An');
      await StationAdminStore.save(draft('thb/1'));
      expect((await StationAdminStore.all()).single.rev, 1);
      // trạm mới KHÔNG được coi là đang hoạt động
      expect((await StationAdminStore.visibleStations()).single.status, StationStatus.unverified);

      final edited = ManagedStation(
          id: 'thb/1', code: 'THB-000001', name: 'Trạm đổi tên', address: '1 Phố Huế, Hà Nội', lat: 21.0, lng: 105.0,
          createdBy: 't', createdAt: DateTime(2026), updatedAt: DateTime(2026));
      await StationAdminStore.save(edited);
      final h = await StationAdminStore.history(stationId: 'thb/1');
      expect(h.first.action, ChangeAction.update);
      expect(h.first.changes['name'], ['Trạm thử', 'Trạm đổi tên']);
      expect(h.first.actor, 'An');
      expect((await StationAdminStore.all()).single.rev, 2);

      final v = await StationAdminStore.setVerified('thb/1', true);
      expect(v!.toStation().status, StationStatus.active);
      expect(v.toStation().category, isNot(StationCategory.datBike));
      await StationAdminStore.setVerified('thb/1', false);
      expect((await StationAdminStore.all()).single.verifiedBy, isNull);

      await StationAdminStore.setHidden('thb/1', 'Trạm đổi tên', true);
      expect(await StationAdminStore.visibleStations(), isEmpty);
      await StationAdminStore.setHidden('osm/9', 'Trạm OSM', true);
      expect((await StationAdminStore.withoutHidden([st('osm/9', 1, 1), st('k', 2, 2)])).map((e) => e.id), ['k']);

      expect(await StationAdminStore.exportCsv(), startsWith('code,id,name'));
      expect(await StationAdminStore.exportJson(), contains('changeLog'));
      await StationAdminStore.delete('thb/1');
      expect(await StationAdminStore.all(), isEmpty);
    });
    test('duyệt đề xuất → chưa xác minh, gỡ khỏi hàng chờ', () async {
      StationAdminAuth.debugSet(admin: true);
      final r = await StationProposalStore.submit(name: 'Quán A', address: '2 Phố Huế, Hà Nội', lat: 21.01, lng: 105.01);
      final m = await StationAdminStore.approveProposal(r.saved!);
      expect(m.verified, false);
      expect(await StationProposalStore.all(), isEmpty);
    });
    test('validate, gần/trùng và CSV', () {
      expect(StationAdminStore.validate(name: 'ab', address: 'địa chỉ dài', lat: 1, lng: 1), isNotNull);
      expect(StationAdminStore.validate(name: 'Trạm A', address: 'địa chỉ dài', lat: 0, lng: 0), isNotNull);
      expect(StationAdminStore.validate(name: 'Trạm A', address: 'địa chỉ dài', lat: 21, lng: 105, ports: 0), isNotNull);
      expect(StationAdminStore.validate(name: 'Trạm A', address: 'địa chỉ dài', lat: 21, lng: 105, ports: 2, powerKw: 7), isNull);
      final n = StationAdminStore.nearest(21.0, 105.0, [st('a', 21.0001, 105.0), st('b', 22, 105)])!;
      expect(n.station.id, 'a');
      expect(n.meters, lessThan(StationAdminStore.nearMeters));
      expect(StationAdminStore.nearest(21, 105, [st('a', 21, 105)], excludeId: 'a'), isNull);
      final csv = StationAdminStore.toCsv([ManagedStation(id: 'i', code: 'c', name: 'A, "B"', address: 'x', lat: 1, lng: 2, createdBy: 'u', createdAt: DateTime(2026), updatedAt: DateTime(2026))]);
      expect(csv, contains('"A, ""B"""'));
    });
    test('PIN: tạo, mở khóa, sai bị từ chối, khóa tạm', () async {
      expect(StationAdminAuth.validatePin('12'), isNotNull);
      expect(await StationAdminAuth.setupPin('1234', 'An'), isNull);
      StationAdminAuth.lock();
      expect(await StationAdminAuth.unlock('0000'), isNotNull);
      expect(StationAdminAuth.isAdmin, false);
      expect(await StationAdminAuth.unlock('1234'), isNull);
      expect(StationAdminAuth.isAdmin, true);
      final t = DateTime(2026, 1, 1);
      StationAdminAuth.lock();
      for (var i = 0; i < StationAdminAuth.maxFails; i++) {
        await StationAdminAuth.unlock('x', now: t);
      }
      expect(await StationAdminAuth.unlock('1234', now: t), contains('Thử lại sau'));
    });
  });

  group('đồng bộ & dẫn đường', () {
    test('chưa có Backend → không báo thành công, không mất bản ghi', () async {
      await StationLogStore.record(StationEvent.view, stationId: 'a');
      final r = await StationSyncService.syncNow();
      expect(r.ok, false);
      expect((await StationSyncService.status()).pending, 1);
      expect((await StationSyncService.status()).configured, false);
    });
    test('liên kết Directions của Google Maps, không cần API key', () {
      final u = ExternalNav.directionsUri(const LatLng(21.04831, 105.881862));
      expect(u.host, 'www.google.com');
      expect(u.path, '/maps/dir/');
      expect(u.queryParameters['api'], '1');
      expect(u.queryParameters['destination'], '21.04831,105.881862');
      expect(u.queryParameters.containsKey('key'), false);
      expect(ExternalNav.directionsUri(const LatLng(1, 2), mode: NavMode.walk).queryParameters['travelmode'], 'walking');
      final t = ExternalNav.navigationTargets(const LatLng(1, 2), 'A B', mode: NavMode.motorbike);
      expect(t.first, 'google.navigation:q=1.0,2.0&mode=l');
      expect(t.length, 3);
      expect(ExternalNav.navigationTargets(const LatLng(1, 2), 'x').length, 2);
    });
  });
}
