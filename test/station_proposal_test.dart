import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mybike_app/core/charging/external_nav.dart';
import 'package:mybike_app/core/charging/station_proposal_store.dart';
import 'package:mybike_app/core/charging/station_repository.dart';
import 'package:mybike_app/core/charging/station_search.dart';
import 'package:mybike_app/core/services/charging_station_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('validate: bắt thiếu tên, địa chỉ, tọa độ sai', () {
    expect(StationProposalStore.validate(name: 'ab', address: 'Hà Nội, VN', lat: 21, lng: 105).ok, false);
    expect(StationProposalStore.validate(name: 'Trạm A', address: '1', lat: 21, lng: 105).ok, false);
    expect(StationProposalStore.validate(name: 'Trạm A', address: 'Hà Nội, VN', lat: null, lng: 105).ok, false);
    expect(StationProposalStore.validate(name: 'Trạm A', address: 'Hà Nội, VN', lat: 95, lng: 105).ok, false);
    expect(StationProposalStore.validate(name: 'Trạm A', address: 'Hà Nội, VN', lat: 21, lng: 105).ok, true);
  });

  test('parseLatLng: dấu chấm, dấu phẩy thập phân, rác', () {
    final a = StationProposalStore.parseLatLng('21.04831, 105.881862')!;
    expect((a.lat, a.lng), (21.04831, 105.881862));
    final b = StationProposalStore.parseLatLng('21,04831 105,881862')!;
    expect((b.lat, b.lng), (21.04831, 105.881862));
    expect(StationProposalStore.parseLatLng('abc'), isNull);
    expect(StationProposalStore.parseLatLng('21.0'), isNull);
  });

  test('đề xuất luôn là cộng đồng, chờ xác minh, không nhãn Dat Bike', () async {
    final r = await StationProposalStore.submit(
        name: 'Quán cà phê có sạc', address: '1 Phố Huế, Hà Nội', lat: 21.01, lng: 105.85);
    final s = r.saved!.toStation();
    expect(s.category, StationCategory.community);
    expect(s.status, StationStatus.unverified);
    expect(s.chargingConfirmed, false);
    expect(s.source, contains('chờ xác minh'));
    expect((await StationProposalStore.all()).length, 1);
  });

  test('chống trùng với dữ liệu có sẵn và đề xuất trước đó', () async {
    const existing = ChargingStation(
        id: 'datbike/x', name: 'Dat Bike X', lat: 21.04831, lng: 105.881862, category: StationCategory.datBike);
    final dup = await StationProposalStore.submit(
        name: 'dat bike x', address: '116 Nguyễn Văn Cừ', lat: 21.04832, lng: 105.881862, existing: [existing]);
    expect(dup.saved, isNull);
    expect(dup.duplicateOf!.id, 'datbike/x');

    await StationProposalStore.submit(name: 'Điểm B', address: 'Địa chỉ B, HN', lat: 21.2, lng: 105.9);
    final again = await StationProposalStore.submit(name: 'Điểm B', address: 'Địa chỉ B, HN', lat: 21.2, lng: 105.9);
    expect(again.saved, isNull);
    expect((await StationProposalStore.all()).length, 1);
  });

  test('đề xuất đã lưu xuất hiện trong fetchNear (offline) với loại cộng đồng', () async {
    await StationProposalStore.submit(name: 'Điểm C', address: 'Địa chỉ C, HN', lat: 21.3, lng: 105.9);
    final r = await StationRepository.fetchNear(21.3, 105.9,
        endpoints: const ['http://127.0.0.1:1/x'],
        timeout: const Duration(milliseconds: 100),
        delay: Duration.zero,
        seedLoader: () async => const []);
    expect(r.stations.single.category, StationCategory.community);
  });

  test('xuất JSON để kiểm duyệt bên ngoài', () async {
    await StationProposalStore.submit(name: 'Điểm D', address: 'Địa chỉ D, HN', lat: 21.4, lng: 105.9);
    final j = await StationProposalStore.exportJson();
    expect(j, contains('Điểm D'));
    expect(j, contains('"state": "pending"'));
  });

  test('bộ lọc loại điểm sạc', () {
    const a = ChargingStation(id: '1', name: 'A', lat: 21, lng: 105, category: StationCategory.datBike);
    const b = ChargingStation(id: '2', name: 'B', lat: 21.001, lng: 105, category: StationCategory.community);
    final all = [a, b];
    const o = LatLng(21, 105);
    expect(StationSearch.apply(all, const StationFilter(), origin: o).length, 2);
    final only = StationSearch.apply(all, const StationFilter(categories: {StationCategory.datBike}), origin: o);
    expect(only.map((e) => e.station.id), ['1']);
    expect(const StationFilter(categories: {StationCategory.datBike}).advancedCount, 1);
  });

  test('telUri chuẩn hóa số điện thoại, từ chối số không hợp lệ', () {
    expect(ExternalNav.telUri('0912 345 678'), 'tel:0912345678');
    expect(ExternalNav.telUri('+84 912-345-678; 0123456789'), 'tel:+84912345678');
    expect(ExternalNav.telUri(null), isNull);
    expect(ExternalNav.telUri('abc'), isNull);
    expect(ExternalNav.telUri('12'), isNull);
  });
}
