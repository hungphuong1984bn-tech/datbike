// Test bộ đếm chẩn đoán BLE — Unit Test.

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_diag_stats.dart';

final _t0 = DateTime(2026, 10, 31, 12);
DateTime _ms(int ms) => _t0.add(Duration(milliseconds: ms));

void main() {
  test('trạng thái ban đầu rỗng, không bịa số', () {
    final s = BleDiagStats();
    expect(s.packetsReceived, 0);
    expect(s.averagePacketIntervalMs, isNull);
    expect(s.errorRate, isNull);
    expect(s.lastPacketAt, isNull);
    expect(s.auth, AuthObserved.none);
  });

  test('đếm gói theo loại và tính chu kỳ trung bình', () {
    final s = BleDiagStats();
    s.recordPacket('dashboard', _ms(0));
    s.recordPacket('dashboard', _ms(700));
    s.recordPacket('battery', _ms(1500));
    expect(s.packetsReceived, 3);
    expect(s.packetsByKind['dashboard'], 2);
    expect(s.packetsByKind['battery'], 1);
    expect(s.averagePacketIntervalMs, closeTo(750, 1e-9));
    expect(s.lastPacketAt, _ms(1500));
  });

  test('chỉ giữ tối đa 50 khoảng cách gần nhất', () {
    final s = BleDiagStats();
    for (var i = 0; i < 200; i++) {
      s.recordPacket('dashboard', _ms(i * 100));
    }
    expect(s.packetsReceived, 200);
    expect(s.averagePacketIntervalMs, closeTo(100, 1e-9));
  });

  test('tỷ lệ lỗi', () {
    final s = BleDiagStats();
    s.recordPacket('dashboard', _ms(0));
    s.recordPacket('dashboard', _ms(10));
    s.recordPacket('dashboard', _ms(20));
    s.recordPacketError('dashboard_parse', detail: 'x', at: _ms(30));
    expect(s.packetErrors, 1);
    expect(s.errorRate, closeTo(0.25, 1e-9));
    expect(s.lastErrorKind, 'dashboard_parse');
    expect(s.lastErrorAt, _ms(30));
  });

  test('kết nối mới xóa mốc gói cũ (không nối khoảng cách giữa hai kết nối)', () {
    final s = BleDiagStats();
    s.recordPacket('dashboard', _ms(0));
    s.recordPacket('dashboard', _ms(100));
    s.recordConnected(_ms(60000));
    expect(s.lastPacketAt, isNull);
    s.recordPacket('dashboard', _ms(60100));
    s.recordPacket('dashboard', _ms(60300));
    expect(s.averagePacketIntervalMs, closeTo(200, 1e-9));
    expect(s.connectedAt, _ms(60000));
  });

  test('ngắt kết nối: đếm, phân biệt thủ công/ngoài ý muốn, xóa xác thực', () {
    final s = BleDiagStats();
    s.recordConnected(_ms(0));
    s.recordAuth(AuthObserved.accepted, _ms(10));
    s.recordDisconnect(manual: false, at: _ms(100));
    expect(s.disconnects, 1);
    expect(s.unexpectedDisconnects, 1);
    expect(s.lastDisconnectAt, _ms(100));
    expect(s.connectedAt, isNull);
    expect(s.auth, AuthObserved.none);
    s.recordDisconnect(manual: true, at: _ms(200));
    expect(s.disconnects, 2);
    expect(s.unexpectedDisconnects, 1);
  });

  test('lỗi kết nối ghi bước, loại, mã', () {
    final s = BleDiagStats();
    s.recordConnectAttempt();
    s.recordConnectFailure(stage: 'gattConnect', kind: 'gattConnectFailed', code: 133, at: _ms(5));
    expect(s.connectAttempts, 1);
    expect(s.connectFailures, 1);
    expect(s.lastFailureStage, 'gattConnect');
    expect(s.lastFailureCode, 133);
  });

  test('kết quả notify theo UUID (không phân biệt hoa thường)', () {
    final s = BleDiagStats();
    s.recordNotify('ABCD', NotifyOutcome.unsupported, at: _ms(0));
    s.recordNotify('abcd', NotifyOutcome.subscribed, at: _ms(1));
    expect(s.notifyResults.length, 1);
    expect(s.notifyResults['abcd']!.outcome, NotifyOutcome.subscribed);
  });

  test('toJson không chứa payload thô, có các trường chính; reset xóa sạch', () {
    final s = BleDiagStats();
    s.recordPacket('dashboard', _ms(0));
    s.recordNotify('abcd', NotifyOutcome.failed, at: _ms(0));
    final j = s.toJson();
    expect(j['packetsReceived'], 1);
    expect((j['notify'] as Map).containsKey('abcd'), isTrue);
    s.reset();
    expect(s.packetsReceived, 0);
    expect(s.notifyResults, isEmpty);
    expect(s.lastPacketAt, isNull);
  });
}
