// Kiểm thử logic thuần của tab Tổng quan (không cần BLE/GPS).

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mybike_app/core/control/mode_types.dart';
import 'package:mybike_app/core/services/charging_station_service.dart';
import 'package:mybike_app/features/home/overview_control_summary.dart';
import 'package:mybike_app/features/home/overview_station.dart';
import 'package:mybike_app/ui/ds/ds_tokens.dart';

void main() {
  group('summarizeMode — không bao giờ coi cache là "đang bật"', () {
    test('chưa đọc từ xe → CHƯA ĐỌC, không phải BẬT/TẮT', () {
      final v = summarizeMode(const ModeState(phase: ModePhase.unread));
      expect(v.value, 'CHƯA ĐỌC');
      expect(v.known, isFalse);
    });

    test('chưa kết nối → CHƯA KẾT NỐI', () {
      final v = summarizeMode(const ModeState(phase: ModePhase.disconnected, on: true));
      expect(v.value, 'CHƯA KẾT NỐI');
      expect(v.known, isFalse);
    });

    test('đã đọc từ xe: BẬT / TẮT', () {
      final on = summarizeMode(const ModeState(phase: ModePhase.ready, on: true));
      final off = summarizeMode(const ModeState(phase: ModePhase.confirmed, on: false));
      expect(on.value, 'BẬT');
      expect(on.known, isTrue);
      expect(on.tone, Severity.ok);
      expect(off.value, 'TẮT');
      expect(off.caption, 'Đã xác nhận từ xe');
    });

    test('giá trị lạ (on == null) → GIÁ TRỊ LẠ', () {
      final v = summarizeMode(const ModeState(phase: ModePhase.ready));
      expect(v.value, 'GIÁ TRỊ LẠ');
      expect(v.known, isFalse);
    });

    test('không xác nhận → mức nghiêm trọng', () {
      final v = summarizeMode(const ModeState(phase: ModePhase.notConfirmed));
      expect(v.tone, Severity.critical);
    });
  });

  group('pickNearestStation', () {
    ChargingStation st(String id, double lat, double lng) =>
        ChargingStation(id: id, name: id, lat: lat, lng: lng, source: 'OpenStreetMap');

    test('danh sách rỗng → null', () {
      expect(pickNearestStation(const [], searchCenter: const LatLng(21, 105)), isNull);
    });

    test('không có vị trí điện thoại → xếp theo điểm tìm kiếm, không có km', () {
      final r = pickNearestStation(
        [st('xa', 21.10, 105.10), st('gan', 21.001, 105.001)],
        searchCenter: const LatLng(21, 105),
      );
      expect(r!.station.id, 'gan');
      expect(r.distanceKm, isNull);
    });

    test('có vị trí điện thoại → xếp theo điện thoại và có km', () {
      final r = pickNearestStation(
        [st('a', 21.001, 105.001), st('b', 21.05, 105.05)],
        searchCenter: const LatLng(21, 105),
        me: const LatLng(21.05, 105.049),
      );
      expect(r!.station.id, 'b');
      expect(r.distanceKm, isNotNull);
      expect(r.distanceKm!, lessThan(1.0));
    });
  });
}
