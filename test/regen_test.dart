import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_controller.dart';
import 'package:mybike_app/core/ble/gatt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mybike_app/core/regen/regen_controller.dart';
import 'package:mybike_app/core/regen/regen_protocol.dart';
import 'package:mybike_app/features/regen/regen_screen.dart';

/// Transport GIẢ — CHỈ dùng trong test để kiểm tra máy trạng thái.
/// Không phải mô phỏng xe thật và không có trong app.
class _MockBle extends BleController {
  @override
  BleState build() => const BleState(phase: BlePhase.connected);
}

class FakeTransport implements RegenTransport {
  int? raw;
  bool acceptWrite = true;
  bool applyWrite = true; // false = xe nhận lệnh nhưng không đổi
  bool throwOnWrite = false;
  bool readFails = false;
  int writes = 0;
  int storeMax = 99; // firmware kiểu boolean: giá trị > storeMax bị gộp về 0
  void Function()? onWrite;

  FakeTransport(this.raw);

  @override
  Future<int?> readRaw() async => readFails ? null : raw;

  @override
  Future<bool> writeRaw(int v) async {
    writes++;
    onWrite?.call();
    if (throwOnWrite) throw Exception('GATT 133');
    if (!acceptWrite) return false;
    if (applyWrite) raw = v <= storeMax ? v : 0;
    return true;
  }
}

// Spec GIẢ chỉ dùng trong test (giá trị không phải của xe thật).
const _testSpec = RegenProtocolSpec(
  verified: true,
  characteristicUuid: 'test-only',
  requiresStandstill: true,
  evidence: 'test',
  levels: [
    RegenLevel(index: 0, label: 'L0', rawValue: 10),
    RegenLevel(index: 1, label: 'L1', rawValue: 11),
    RegenLevel(index: 2, label: 'L2', rawValue: 12),
  ],
);

const _stopped = RegenLinkInfo(
    connected: true, authorized: true, telemetryFresh: true, speedKmh: 0);

ProviderContainer _container({
  required RegenTransport transport,
  RegenProtocolSpec spec = _testSpec,
  RegenLinkInfo Function()? link,
}) {
  return ProviderContainer(overrides: [
    regenSpecProvider.overrideWithValue(spec),
    regenTransportProvider.overrideWithValue(transport),
    regenReadbackDelayProvider.overrideWithValue(Duration.zero),
    regenLinkReaderProvider.overrideWithValue(link ?? () => _stopped),
  ]);
}

void main() {
  group('Cổng an toàn', () {
    test('chặn khi chạy, thiếu telemetry mới, chưa biết tốc độ, mất kết nối', () {
      expect(
          regenBlockReason(
              const RegenLinkInfo(connected: true, authorized: true, telemetryFresh: true, speedKmh: 12),
              requiresStandstill: true),
          isNotNull);
      expect(
          regenBlockReason(
              const RegenLinkInfo(connected: true, authorized: true, telemetryFresh: false, speedKmh: 0),
              requiresStandstill: true),
          isNotNull);
      expect(
          regenBlockReason(
              const RegenLinkInfo(connected: true, authorized: true, telemetryFresh: true, speedKmh: null),
              requiresStandstill: true),
          isNotNull);
      expect(
          regenBlockReason(
              const RegenLinkInfo(connected: false, authorized: false, telemetryFresh: false, speedKmh: null),
              requiresStandstill: true),
          isNotNull);
      expect(regenBlockReason(_stopped, requiresStandstill: true), isNull);
    });
  });

  group('Giao thức chưa xác minh (mặc định của app)', () {
    test('apply() không gửi gì xuống xe', () async {
      final t = FakeTransport(10);
      final c = _container(transport: t, spec: RegenProtocolSpec.unverified);
      addTearDown(c.dispose);
      expect(c.read(regenProvider).status, RegenSyncStatus.unsupported);
      await c.read(regenProvider.notifier).apply();
      expect(t.writes, 0);
      expect(c.read(regenProvider).status, RegenSyncStatus.unsupported);
    });

    test('spec Grab mặc định: chỉ 0/1, mức >= 2 đánh dấu thử nghiệm', () {
      final spec = RegenProtocolSpec.grab();
      expect(spec.verified, isTrue);
      expect(spec.characteristicUuid, Gatt.grabModeChar);
      expect(spec.levels.length, 2);
      final s4 = RegenProtocolSpec.grab(maxLevel: 4);
      expect(s4.levels.length, 5);
      expect(s4.levels.where((l) => l.experimental).map((l) => l.index), [2, 3, 4]);
    });
  });

  group('Máy trạng thái khi đã xác minh (spec/transport giả trong test)', () {
    test('đổi mức → ghi → đọc lại khớp → synced', () async {
      final t = FakeTransport(10);
      final c = _container(transport: t);
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      expect(c.read(regenProvider).currentIndex, 0);
      n.select(2);
      expect(c.read(regenProvider).status, RegenSyncStatus.pending);
      await n.apply();
      final s = c.read(regenProvider);
      expect(t.writes, 1);
      expect(s.status, RegenSyncStatus.synced);
      expect(s.currentIndex, 2);
    });

    test('xe nhận lệnh nhưng không đổi → mismatch, không báo thành công', () async {
      final t = FakeTransport(10)..applyWrite = false;
      final c = _container(transport: t);
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      n.select(1);
      await n.apply();
      final s = c.read(regenProvider);
      expect(s.status, RegenSyncStatus.mismatch);
      expect(s.currentIndex, 0);
    });

    test('xe từ chối lệnh → failed', () async {
      final t = FakeTransport(10)..acceptWrite = false;
      final c = _container(transport: t);
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      n.select(1);
      await n.apply();
      expect(c.read(regenProvider).status, RegenSyncStatus.failed);
    });

    test('lỗi GATT khi ghi → failed', () async {
      final t = FakeTransport(10)..throwOnWrite = true;
      final c = _container(transport: t);
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      n.select(1);
      await n.apply();
      expect(c.read(regenProvider).status, RegenSyncStatus.failed);
    });

    test('đọc lại thất bại sau khi ghi → failed (không synced)', () async {
      final t = FakeTransport(10);
      final c = _container(transport: t);
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      n.select(1);
      t.readFails = true;
      await n.apply();
      expect(c.read(regenProvider).status, RegenSyncStatus.failed);
    });

    test('xe báo giá trị thô lạ → mismatch', () async {
      final t = FakeTransport(99);
      final c = _container(transport: t);
      addTearDown(c.dispose);
      await c.read(regenProvider.notifier).refresh();
      final s = c.read(regenProvider);
      expect(s.status, RegenSyncStatus.mismatch);
      expect(s.currentIndex, isNull);
      expect(s.currentRaw, 99);
    });

    test('xe đang chạy → chặn, không ghi', () async {
      final t = FakeTransport(10);
      var speed = 0.0;
      final c = _container(
        transport: t,
        link: () => RegenLinkInfo(
            connected: true, authorized: true, telemetryFresh: true, speedKmh: speed),
      );
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      n.select(1);
      speed = 25;
      await n.apply();
      expect(t.writes, 0);
      expect(c.read(regenProvider).status, RegenSyncStatus.failed);
    });

    test('mất kết nối sau khi ghi → failed, không synced', () async {
      final t = FakeTransport(10);
      var connected = true;
      final c = _container(
        transport: t,
        link: () => RegenLinkInfo(
            connected: connected, authorized: connected, telemetryFresh: true, speedKmh: 0),
      );
      addTearDown(c.dispose);
      final n = c.read(regenProvider.notifier);
      await n.refresh();
      n.select(1);
      // xe nhận lệnh rồi rớt kết nối ngay sau đó
      t.onWrite = () => connected = false;
      await n.apply();
      expect(t.writes, 1);
      expect(c.read(regenProvider).status, RegenSyncStatus.failed);
    });

    test('step() không đoán khi chưa biết mức trên xe', () {
      final t = FakeTransport(10);
      final c = _container(transport: t);
      addTearDown(c.dispose);
      c.read(regenProvider.notifier).step(1);
      expect(c.read(regenProvider).selectedIndex, isNull);
    });
  });

  group('Dò mức Grab có kiểm soát', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('firmware boolean (gộp >1 về 0): dừng ở mức 2, khôi phục mức ban đầu', () async {
      final t = FakeTransport(1)..storeMax = 1;
      final c = _container(transport: t, spec: RegenProtocolSpec.grab());
      addTearDown(c.dispose);
      await c.read(regenProvider.notifier).probeHigherLevels();
      expect(c.read(grabMaxLevelProvider), 1);
      expect(t.raw, 1); // đã khôi phục
      expect(c.read(regenProvider).message, contains('Chỉ mức 0/1'));
    });

    test('xe lưu được tới mức 3: ghi nhận mức tối đa 3 và khôi phục ban đầu', () async {
      final t = FakeTransport(0)..storeMax = 3;
      final c = _container(transport: t, spec: RegenProtocolSpec.grab());
      addTearDown(c.dispose);
      await c.read(regenProvider.notifier).probeHigherLevels();
      expect(c.read(grabMaxLevelProvider), 3);
      expect(t.raw, 0);
      expect(c.read(regenProvider).message, contains('CHƯA xác minh'));
    });

    test('xe đang chạy → không ghi gì khi dò', () async {
      final t = FakeTransport(0);
      final c = _container(
        transport: t,
        spec: RegenProtocolSpec.grab(),
        link: () => const RegenLinkInfo(
            connected: true, authorized: true, telemetryFresh: true, speedKmh: 20),
      );
      addTearDown(c.dispose);
      await c.read(regenProvider.notifier).probeHigherLevels();
      expect(t.writes, 0);
      expect(c.read(regenProvider).status, RegenSyncStatus.failed);
    });

    test('không đọc được mức ban đầu → không ghi gì', () async {
      final t = FakeTransport(0)..readFails = true;
      final c = _container(transport: t, spec: RegenProtocolSpec.grab());
      addTearDown(c.dispose);
      await c.read(regenProvider.notifier).probeHigherLevels();
      expect(t.writes, 0);
    });
  });

  group('Giao diện', () {
    Widget host(RegenProtocolSpec spec, FakeTransport t) => ProviderScope(
          overrides: [
            bleProvider.overrideWith(() => _MockBle()),
            regenSpecProvider.overrideWithValue(spec),
            regenTransportProvider.overrideWithValue(t),
          ],
          child: const MaterialApp(home: RegenScreen()),
        );

    testWidgets('chưa xác minh: hiện cảnh báo, khóa nút gửi, không tràn 320dp', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(host(RegenProtocolSpec.unverified, FakeTransport(null)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('regen_unsupported_banner')), findsOneWidget);
      expect(find.byKey(const Key('regen_no_levels')), findsOneWidget);
      final apply = tester.widget<FilledButton>(find.byKey(const Key('regen_apply')));
      expect(apply.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Grab nhiều mức: hiện các mức, nút dò, bảng đo, không tràn 320dp', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 800 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(host(RegenProtocolSpec.grab(maxLevel: 3), FakeTransport(1)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('regen_unsupported_banner')), findsNothing);
      expect(find.text('Regen mức 3 (thử nghiệm)', skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('regen_probe'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('regen_live_meter'), skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
