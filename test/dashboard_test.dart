// Kiểm thử tự động (đơn vị) cho App Dashboard + Dashboard Sync.
// Dữ liệu xe trong test là MÔ PHỎNG do test dựng, không phải đo từ xe thật.

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/dashboard/dashboard_model.dart';
import 'package:mybike_app/core/dashboard/dashboard_sync.dart';
import 'package:mybike_app/core/proto/bike_log.dart';

BikeLogMsg _bike() {
  final m = BikeLogMsg();
  m.speed = 35.4;
  m.odo = 9721.8;
  m.voltage = 76.7;
  m.percent = 63;
  m.phase = -12.0;
  m.kmLeft = 80;
  m.state = BikeState.drive;
  m.left = true;
  return m;
}

class _FakeTransport implements DisplaySyncTransport {
  @override
  bool connected = true;
  int writes = 0;
  bool ack = true;
  bool throwOnWrite = false;
  @override
  Future<void> writeChunk(List<int> chunk) async {
    writes++;
    if (throwOnWrite) throw Exception('GATT 133');
  }

  @override
  Future<bool> waitAck(Duration timeout) async => ack;
}

void main() {
  group('resolveDash — không số giả', () {
    test('xe live → giá trị thật, nguồn = XE', () {
      final v = resolveDash(
          DashInput(bike: _bike(), bikeLive: true, bleConnected: true));
      expect(v[DashWidgetId.speed]!.text, equals('35'));
      expect(v[DashWidgetId.speed]!.source, equals(DashSource.bike));
      expect(v[DashWidgetId.battery]!.text, equals('63'));
      expect(v[DashWidgetId.odo]!.text, equals('9721.8'));
    });
    test('dữ liệu cũ (bikeLive=false) → "--", không hiện số cũ', () {
      final v = resolveDash(
          DashInput(bike: _bike(), bikeLive: false, bleConnected: true));
      for (final id in [
        DashWidgetId.speed,
        DashWidgetId.battery,
        DashWidgetId.voltage,
        DashWidgetId.odo,
        DashWidgetId.range
      ]) {
        expect(v[id]!.text, equals('--'));
        expect(v[id]!.available, isFalse);
      }
    });
    test('không có bike → toàn bộ giá trị từ xe là "--"', () {
      final v = resolveDash(
          const DashInput(bike: null, bikeLive: false, bleConnected: false));
      expect(v[DashWidgetId.speed]!.text, equals('--'));
      expect(v[DashWidgetId.mode]!.available, isFalse);
      expect(v[DashWidgetId.bluetooth]!.text, equals('MẤT KẾT NỐI'));
    });
    test('đèn pha LUÔN "--" (telemetry không có trường này)', () {
      final v = resolveDash(
          DashInput(bike: _bike(), bikeLive: true, bleConnected: true));
      expect(v[DashWidgetId.headlight]!.text, equals('--'));
      expect(v[DashWidgetId.headlight]!.available, isFalse);
    });
    test('GPS tách riêng khỏi tốc độ xe', () {
      final v = resolveDash(DashInput(
          bike: null,
          bikeLive: false,
          bleConnected: false,
          gpsKmh: 28.2,
          gpsLive: true));
      expect(v[DashWidgetId.speed]!.text, equals('--'));
      expect(v[DashWidgetId.gpsSpeed]!.text, equals('28'));
      expect(v[DashWidgetId.gpsSpeed]!.source, equals(DashSource.phone));
    });
    test('GPS cũ → "--"', () {
      final v = resolveDash(const DashInput(
          bike: null,
          bikeLive: false,
          bleConnected: false,
          gpsKmh: 28.2,
          gpsLive: false));
      expect(v[DashWidgetId.gpsSpeed]!.text, equals('--'));
    });
    test('công suất là dữ liệu TÍNH TOÁN, không phải từ xe', () {
      final v = resolveDash(
          DashInput(bike: _bike(), bikeLive: true, bleConnected: true));
      expect(v[DashWidgetId.power]!.source, equals(DashSource.derived));
    });
    test('Regen chỉ hiện khi đã đọc lại từ xe', () {
      final a = resolveDash(
          DashInput(bike: _bike(), bikeLive: true, bleConnected: true));
      expect(a[DashWidgetId.regen]!.text, equals('--'));
      final b = resolveDash(DashInput(
          bike: _bike(), bikeLive: true, bleConnected: true, regenLevel: 1));
      expect(b[DashWidgetId.regen]!.text, equals('1'));
      final c = resolveDash(DashInput(
          bike: _bike(), bikeLive: true, bleConnected: false, regenLevel: 1));
      expect(c[DashWidgetId.regen]!.text, equals('--'));
    });
    test('giá trị vô lý (NaN / quá giới hạn) bị loại', () {
      final m = _bike()..speed = double.nan;
      final v = resolveDash(DashInput(bike: m, bikeLive: true, bleConnected: true));
      expect(v[DashWidgetId.speed]!.text, equals('--'));
      final m2 = _bike()..voltage = 5000;
      final v2 = resolveDash(DashInput(bike: m2, bikeLive: true, bleConnected: true));
      expect(v2[DashWidgetId.voltage]!.text, equals('--'));
      expect(v2[DashWidgetId.power]!.text, equals('--'));
    });
    test('tốc độ ~0 hiển thị 0, không phải "0.0002"', () {
      final m = _bike()..speed = 0.0002;
      final v = resolveDash(DashInput(bike: m, bikeLive: true, bleConnected: true));
      expect(v[DashWidgetId.speed]!.text, equals('0'));
    });
  });

  group('Profile lưu/khôi phục', () {
    test('mã hóa rồi giải mã giữ nguyên cấu hình', () {
      final p = const DashProfile(id: 'a', name: 'Đi phố').copyWith(
          theme: DashTheme.cyber,
          layout: DashLayout.focus,
          accent: 0xFF00FFAA,
          widgets: [DashWidgetId.speed, DashWidgetId.battery],
          alwaysOn: false);
      final data = DashStoreData([p, const DashProfile(id: 'b', name: 'B')], 'a');
      final back = DashStoreData.decode(data.encode());
      expect(back.profiles.length, equals(2));
      expect(back.activeId, equals('a'));
      expect(back.active.theme, equals(DashTheme.cyber));
      expect(back.active.layout, equals(DashLayout.focus));
      expect(back.active.accent, equals(0xFF00FFAA));
      expect(back.active.widgets.length, equals(2));
      expect(back.active.alwaysOn, isFalse);
    });
    test('dữ liệu hỏng → seed, không ném lỗi', () {
      expect(DashStoreData.decode('{không phải json').profiles.length, equals(1));
      expect(DashStoreData.decode(null).profiles.length, equals(1));
      expect(DashStoreData.decode('[]').profiles.length, equals(1));
      expect(DashStoreData.decode('{"profiles":[1,2,3]}').profiles.length,
          equals(1));
    });
    test('active không tồn tại → chuyển về profile đầu', () {
      final raw = '{"active":"zzz","profiles":[{"id":"a","name":"A"}]}';
      expect(DashStoreData.decode(raw).activeId, equals('a'));
    });
    test('enum lạ/widget lạ → mặc định, bỏ widget trùng', () {
      final raw =
          '{"active":"a","profiles":[{"id":"a","theme":"hologram","widgets":["speed","speed","??"]}]}';
      final p = DashStoreData.decode(raw).active;
      expect(p.theme, equals(DashTheme.sport));
      expect(p.widgets.length, equals(1));
    });
    test('id trùng chỉ giữ cái đầu', () {
      final raw =
          '{"profiles":[{"id":"a","name":"X"},{"id":"a","name":"Y"}]}';
      expect(DashStoreData.decode(raw).profiles.length, equals(1));
    });
  });

  group('Dashboard Sync', () {
    test('mặc định: unsupported, KHÔNG cho hiện nút đồng bộ', () {
      final e = DashboardSyncEngine();
      expect(e.state.status, equals(DisplaySyncStatus.unsupported));
      expect(e.canOfferSync, isFalse);
      expect(DisplaySyncSpec.unverified.evidence.isNotEmpty, isTrue);
    });
    test('chưa xác minh → send không gọi transport, không báo thành công', () async {
      final t = _FakeTransport();
      final e = DashboardSyncEngine(transport: t); // spec mặc định unverified
      final s = await e.send([1, 2, 3]);
      expect(s.status, equals(DisplaySyncStatus.unsupported));
      expect(t.writes, equals(0));
    });
    test('spec verified GIẢ (chỉ test): gửi theo chunk rồi done khi có ACK', () async {
      final t = _FakeTransport();
      final e = DashboardSyncEngine(
        spec: const DisplaySyncSpec(
            verified: true,
            characteristicUuid: 'test-only',
            maxChunkBytes: 4,
            maxHz: 0,
            ackTimeout: Duration(milliseconds: 10),
            maxRetries: 1,
            evidence: ['test']),
        transport: t,
      );
      expect(e.canOfferSync, isTrue);
      final s = await e.send(List.generate(10, (i) => i));
      expect(s.status, equals(DisplaySyncStatus.done));
      expect(t.writes, equals(3));
    });
    test('không có ACK → failed (không bao giờ báo done)', () async {
      final t = _FakeTransport()..ack = false;
      final e = DashboardSyncEngine(
        spec: const DisplaySyncSpec(
            verified: true,
            characteristicUuid: 'test-only',
            maxChunkBytes: 8,
            maxHz: 0,
            ackTimeout: Duration(milliseconds: 10),
            maxRetries: 2,
            evidence: ['test']),
        transport: t,
      );
      final s = await e.send([1, 2, 3]);
      expect(s.status, equals(DisplaySyncStatus.failed));
      expect(t.writes, equals(3)); // 1 lần + 2 lần thử lại
    });
    test('ghi lỗi → thử lại rồi failed', () async {
      final t = _FakeTransport()..throwOnWrite = true;
      final e = DashboardSyncEngine(
        spec: const DisplaySyncSpec(
            verified: true,
            characteristicUuid: 'test-only',
            maxChunkBytes: 8,
            maxHz: 0,
            ackTimeout: Duration(milliseconds: 10),
            maxRetries: 1,
            evidence: ['test']),
        transport: t,
      );
      final s = await e.send([1]);
      expect(s.status, equals(DisplaySyncStatus.failed));
    });
    test('chưa kết nối xe → disconnected, không ghi', () async {
      final t = _FakeTransport()..connected = false;
      final e = DashboardSyncEngine(
        spec: const DisplaySyncSpec(
            verified: true,
            characteristicUuid: 'test-only',
            maxChunkBytes: 8,
            maxHz: 0,
            ackTimeout: Duration(milliseconds: 10),
            maxRetries: 0,
            evidence: ['test']),
        transport: t,
      );
      final s = await e.send([1]);
      expect(s.status, equals(DisplaySyncStatus.disconnected));
      expect(t.writes, equals(0));
    });
  });
}
