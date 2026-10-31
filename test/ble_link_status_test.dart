// Test trạng thái liên kết BLE dẫn xuất — Unit Test (mô phỏng, không dùng xe thật).

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_link_status.dart';
import 'package:mybike_app/core/ble/connect_diagnostics.dart' show ConnectStage;

final _t0 = DateTime(2026, 10, 31, 12, 0, 0);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

BleLinkInputs _connected({
  required int nowS,
  int? dataS,
  int? connectedS = 0,
  bool authorized = true,
  bool authInProgress = false,
  bool discovered = true,
}) =>
    BleLinkInputs(
      now: _at(nowS),
      gattConnected: true,
      servicesDiscovered: discovered,
      authorized: authorized,
      authInProgress: authInProgress,
      connectedAt: connectedS == null ? null : _at(connectedS),
      lastDataAt: dataS == null ? null : _at(dataS),
      everConnected: true,
    );

void main() {
  group('ưu tiên cao nhất', () {
    test('Bluetooth tắt thắng mọi thứ', () {
      final s = deriveBleLinkStatus(BleLinkInputs(
          now: _t0, adapterOn: false, gattConnected: true, lastDataAt: _t0));
      expect(s, BleLinkStatus.adapterOff);
    });
    test('thiếu quyền', () {
      expect(
          deriveBleLinkStatus(BleLinkInputs(now: _t0, permissionGranted: false)),
          BleLinkStatus.permissionMissing);
    });
    test('chưa biết adapter/quyền (null) KHÔNG bị coi là tắt/thiếu', () {
      expect(deriveBleLinkStatus(BleLinkInputs(now: _t0)), BleLinkStatus.idle);
    });
    test('đang thử kết nối lại', () {
      expect(
          deriveBleLinkStatus(
              BleLinkInputs(now: _t0, reconnecting: true, everConnected: true)),
          BleLinkStatus.reconnecting);
    });
  });

  group('trước khi có liên kết', () {
    test('quét → tìm thấy → đang kết nối', () {
      expect(deriveBleLinkStatus(BleLinkInputs(now: _t0, scanning: true)),
          BleLinkStatus.scanning);
      expect(
          deriveBleLinkStatus(
              BleLinkInputs(now: _t0, scanning: true, deviceFound: true)),
          BleLinkStatus.deviceFound);
      expect(
          deriveBleLinkStatus(
              BleLinkInputs(now: _t0, deviceFound: true, gattConnecting: true)),
          BleLinkStatus.connecting);
    });
    test('đã từng kết nối mà giờ không còn → mất kết nối; chưa từng → chưa kết nối', () {
      expect(deriveBleLinkStatus(BleLinkInputs(now: _t0, everConnected: true)),
          BleLinkStatus.disconnected);
      expect(deriveBleLinkStatus(BleLinkInputs(now: _t0)), BleLinkStatus.idle);
    });
  });

  group('đã mở GATT: kết nối ≠ có dữ liệu', () {
    test('khám phá dịch vụ', () {
      expect(deriveBleLinkStatus(_connected(nowS: 1, discovered: false)),
          BleLinkStatus.discoveringServices);
    });
    test('đang xác thực', () {
      expect(
          deriveBleLinkStatus(
              _connected(nowS: 2, authInProgress: true, authorized: false)),
          BleLinkStatus.authenticating);
    });
    test('kết nối xong, chưa quá hạn chờ, chưa có dữ liệu → "đã kết nối" (KHÔNG phải nhận dữ liệu)', () {
      final s = deriveBleLinkStatus(_connected(nowS: 3));
      expect(s, BleLinkStatus.connected);
      expect(s.hasLiveData, isFalse);
    });
    test('quá hạn chờ mà không có dữ liệu → kết nối nhưng không có dữ liệu', () {
      final s = deriveBleLinkStatus(_connected(nowS: 20));
      expect(s, BleLinkStatus.connectedNoData);
      expect(s.isLinkUp, isTrue);
      expect(s.hasLiveData, isFalse);
    });
    test('có dữ liệu mới → đang nhận dữ liệu', () {
      final s = deriveBleLinkStatus(_connected(nowS: 21, dataS: 20));
      expect(s, BleLinkStatus.receivingData);
      expect(s.hasLiveData, isTrue);
    });
    test('đúng biên cửa sổ mới (4s) vẫn là mới; quá 1ms là cũ', () {
      expect(deriveBleLinkStatus(_connected(nowS: 24, dataS: 20)),
          BleLinkStatus.receivingData);
      final i = BleLinkInputs(
        now: _at(24).add(const Duration(milliseconds: 1)),
        gattConnected: true,
        servicesDiscovered: true,
        authorized: true,
        connectedAt: _at(0),
        lastDataAt: _at(20),
      );
      expect(deriveBleLinkStatus(i), BleLinkStatus.dataStale);
    });
    test('đã có dữ liệu nhưng ngừng lâu → dữ liệu cũ', () {
      final s = deriveBleLinkStatus(_connected(nowS: 40, dataS: 10));
      expect(s, BleLinkStatus.dataStale);
      expect(s.hasLiveData, isFalse);
    });
    test('dữ liệu có từ TRƯỚC lần kết nối hiện tại bị bỏ qua (không dùng cache như trực tiếp)', () {
      // Dữ liệu lúc t=5, kết nối mới mở lúc t=30 → không được coi là đang nhận dữ liệu.
      final s = deriveBleLinkStatus(
          _connected(nowS: 31, dataS: 5, connectedS: 30));
      expect(s, BleLinkStatus.connected);
      expect(s.hasLiveData, isFalse);
    });
  });

  group('chỉ receivingData là dữ liệu trực tiếp', () {
    test('mọi trạng thái khác hasLiveData=false', () {
      for (final s in BleLinkStatus.values) {
        expect(s.hasLiveData, s == BleLinkStatus.receivingData, reason: s.name);
      }
    });
    test('mọi trạng thái có nhãn và gợi ý tiếng Việt không rỗng', () {
      for (final s in BleLinkStatus.values) {
        expect(s.label, isNotEmpty);
        expect(s.hint, isNotEmpty);
      }
    });
    test('có đủ 13 trạng thái yêu cầu (+ idle)', () {
      expect(BleLinkStatus.values.length, 14);
    });
  });

  group('stageFlagsFor', () {
    test('trước GATT: chưa kết nối', () {
      final f = stageFlagsFor(ConnectStage.gattConnect);
      expect(f.gattConnected, isFalse);
      expect(stageFlagsFor(null).gattConnected, isFalse);
    });
    test('discoverServices: đã mở GATT, chưa khám phá xong', () {
      final f = stageFlagsFor(ConnectStage.discoverServices);
      expect(f.gattConnected, isTrue);
      expect(f.servicesDiscovered, isFalse);
    });
    test('các bước xác thực → authInProgress', () {
      for (final s in [
        ConnectStage.authChallenge,
        ConnectStage.appAuth,
        ConnectStage.authResponse,
        ConnectStage.sessionKey,
        ConnectStage.sessionRegister,
      ]) {
        final f = stageFlagsFor(s);
        expect(f.authInProgress, isTrue, reason: s.name);
        expect(f.authDone, isFalse, reason: s.name);
      }
    });
    test('notifications/telemetry: xác thực xong', () {
      expect(stageFlagsFor(ConnectStage.telemetry).authDone, isTrue);
      expect(stageFlagsFor(ConnectStage.notifications).authInProgress, isFalse);
    });
    test('mọi ConnectStage đều có kết quả (switch đầy đủ)', () {
      for (final s in ConnectStage.values) {
        expect(() => stageFlagsFor(s), returnsNormally);
      }
    });
  });

  group('chất lượng tín hiệu', () {
    test('mốc RSSI', () {
      expect(signalQualityFromRssi(null), SignalQuality.unknown);
      expect(signalQualityFromRssi(-55), SignalQuality.excellent);
      expect(signalQualityFromRssi(-56), SignalQuality.good);
      expect(signalQualityFromRssi(-70), SignalQuality.good);
      expect(signalQualityFromRssi(-85), SignalQuality.fair);
      expect(signalQualityFromRssi(-86), SignalQuality.weak);
    });
    test('có nhãn cho mọi mức', () {
      for (final q in SignalQuality.values) {
        expect(signalQualityLabel(q), isNotEmpty);
      }
    });
  });
}
