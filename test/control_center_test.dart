// Test cho Trung tâm điều khiển vận hành (Grab / ECE / Regen chỉ-đọc).
//
// CÁC LỚP GIẢ Ở ĐÂY CHỈ DÙNG TRONG TEST để kiểm tra máy trạng thái. Chúng KHÔNG
// phải mô phỏng xe thật và không có trong app. Kết quả test không chứng minh xe
// thật phản hồi đúng — việc đó cần thiết bị thật (docs/CONTROL_CENTER.md §6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_controller.dart';
import 'package:mybike_app/core/control/mode_controller.dart';
import 'package:mybike_app/core/control/mode_types.dart';
import 'package:mybike_app/core/control/regen_monitor.dart';
import 'package:mybike_app/core/proto/bike_log.dart';
import 'package:mybike_app/core/regen/regen_controller.dart';
import 'package:mybike_app/core/regen/regen_protocol.dart';
import 'package:mybike_app/features/control_center/control_center_screen.dart';

class _FakeBle extends BleController {
  _FakeBle(this.initial);
  final BleState initial;
  @override
  BleState build() => initial;
  void setPhase(BlePhase p) => state = state.copyWith(phase: p);
}

class _FakeTransport implements ModeTransport {
  _FakeTransport({this.primary, this.secondary, this.pair = false});
  final bool pair; // true = kiểu ECE (2 cờ)
  int? primary;
  int? secondary;
  bool acceptWrite = true;
  bool partialFail = false;
  bool apply = true; // false = xe nhận lệnh nhưng không đổi
  bool secondaryApply = true;
  bool throwOnWrite = false;
  bool readFails = false;
  int writes = 0;
  int reads = 0;
  void Function()? onWrite;

  @override
  Future<ModeSnapshot> read() async {
    reads++;
    if (readFails) return const ModeSnapshot();
    return ModeSnapshot(primaryRaw: primary, secondaryRaw: pair ? secondary : null);
  }

  @override
  Future<ModeWriteResult> write(bool on, String cmdId) async {
    writes++;
    onWrite?.call();
    if (throwOnWrite) throw Exception('GATT 133');
    if (partialFail) {
      return const ModeWriteResult(sent: false, partial: true, error: 'ECE lỗi');
    }
    if (!acceptWrite) return const ModeWriteResult(sent: false, error: 'bị từ chối');
    if (apply) {
      primary = on ? 1 : 0;
      if (pair && secondaryApply) secondary = on ? 1 : 0;
    }
    return const ModeWriteResult(sent: true);
  }
}

const _stopped =
    RegenLinkInfo(connected: true, authorized: true, telemetryFresh: true, speedKmh: 0);

ProviderContainer _container({
  required _FakeTransport grab,
  _FakeTransport? ece,
  RegenLinkInfo Function()? link,
  Duration cooldown = Duration.zero,
  _FakeBle? ble,
}) {
  final fakeBle = ble ??
      _FakeBle(const BleState(phase: BlePhase.connected, isAuthorized: true));
  return ProviderContainer(overrides: [
    bleProvider.overrideWith(() => fakeBle),
    grabTransportProvider.overrideWithValue(grab),
    eceTransportProvider.overrideWithValue(ece ?? _FakeTransport(pair: true)),
    modeReadbackDelayProvider.overrideWithValue(Duration.zero),
    modeCooldownProvider.overrideWithValue(cooldown),
    regenLinkReaderProvider.overrideWithValue(link ?? () => _stopped),
  ]);
}

void main() {
  group('Spec diễn giải giá trị', () {
    test('Grab: chỉ 0/1 được diễn giải; giá trị khác → null (không đoán)', () {
      const s = GrabModeSpec();
      expect(s.interpret(const ModeSnapshot(primaryRaw: 1)), isTrue);
      expect(s.interpret(const ModeSnapshot(primaryRaw: 0)), isFalse);
      expect(s.interpret(const ModeSnapshot(primaryRaw: 2)), isNull);
      expect(s.interpret(const ModeSnapshot()), isNull);
    });

    test('ECE: giới hạn chỉ hiệu lực khi cả ECE và SpeedLimit = 1', () {
      const s = EceModeSpec();
      expect(s.limitEffective(const ModeSnapshot(primaryRaw: 1, secondaryRaw: 1)), isTrue);
      expect(s.limitEffective(const ModeSnapshot(primaryRaw: 1, secondaryRaw: 0)), isFalse);
      expect(s.limitEffective(const ModeSnapshot(primaryRaw: 0, secondaryRaw: 1)), isFalse);
      expect(s.limitEffective(const ModeSnapshot(primaryRaw: 1)), isNull);
      expect(s.matches(const ModeSnapshot(primaryRaw: 1, secondaryRaw: 0), true), isFalse);
      expect(s.matches(const ModeSnapshot(primaryRaw: 1, secondaryRaw: 1), true), isTrue);
      expect(s.matches(const ModeSnapshot(primaryRaw: 0, secondaryRaw: 0), false), isTrue);
    });
  });

  group('Khởi động / kết nối — không tự gửi, không tự bật', () {
    test('khởi tạo: không đọc, không ghi, trạng thái "chưa đọc"', () {
      final g = _FakeTransport(primary: 0);
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      final c = _container(grab: g, ece: e);
      addTearDown(c.dispose);
      expect(c.read(grabModeProvider).phase, ModePhase.unread);
      expect(c.read(eceModeProvider).phase, ModePhase.unread);
      expect(c.read(grabModeProvider).on, isNull); // không có giá trị cache
      expect(c.read(eceModeProvider).on, isNull);
      expect(g.writes + e.writes, 0);
      expect(g.reads + e.reads, 0);
    });

    test('ngắt rồi kết nối lại: không gửi lệnh, quay về "chưa đọc"', () async {
      final g = _FakeTransport(primary: 1);
      final ble = _FakeBle(const BleState(phase: BlePhase.connected, isAuthorized: true));
      final c = _container(grab: g, ble: ble);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).sync();
      expect(c.read(grabModeProvider).on, isTrue);

      ble.setPhase(BlePhase.disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(grabModeProvider).phase, ModePhase.disconnected);
      expect(c.read(grabModeProvider).on, isNull); // không giữ giá trị cũ như thật

      ble.setPhase(BlePhase.connected);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(grabModeProvider).phase, ModePhase.unread);
      expect(c.read(grabModeProvider).on, isNull);
      expect(g.writes, 0);
    });
  });

  group('Grab', () {
    test('sync() phản ánh giá trị thật từ xe và không ghi', () async {
      final g = _FakeTransport(primary: 1);
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).sync();
      final s = c.read(grabModeProvider);
      expect(s.phase, ModePhase.ready);
      expect(s.on, isTrue);
      expect(g.writes, 0);
    });

    test('bật thủ công → ghi → đọc lại khớp → confirmed', () async {
      final g = _FakeTransport(primary: 0);
      final c = _container(grab: g);
      addTearDown(c.dispose);
      final n = c.read(grabModeProvider.notifier);
      await n.sync();
      await n.command(true);
      final s = c.read(grabModeProvider);
      expect(g.writes, 1);
      expect(s.phase, ModePhase.confirmed);
      expect(s.on, isTrue);
      expect(s.lastCommand?.outcome, 'confirmed');
      expect(s.lastCommand?.id, isNotEmpty);
    });

    test('tắt thủ công → confirmed', () async {
      final g = _FakeTransport(primary: 1);
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(false);
      expect(c.read(grabModeProvider).phase, ModePhase.confirmed);
      expect(c.read(grabModeProvider).on, isFalse);
    });

    test('xe nhận lệnh nhưng không đổi → KHÔNG XÁC NHẬN, không thử lại', () async {
      final g = _FakeTransport(primary: 0)..apply = false;
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      final s = c.read(grabModeProvider);
      expect(s.phase, ModePhase.notConfirmed);
      expect(s.message, contains('KHÔNG XÁC NHẬN'));
      expect(s.on, isFalse); // hiển thị giá trị xe thực sự báo
      expect(g.writes, 1);
    });

    test('xe từ chối lệnh → notConfirmed, đúng 1 lệnh', () async {
      final g = _FakeTransport(primary: 0)..acceptWrite = false;
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(c.read(grabModeProvider).phase, ModePhase.notConfirmed);
      expect(g.writes, 1);
    });

    test('lỗi GATT khi ghi → notConfirmed', () async {
      final g = _FakeTransport(primary: 0)..throwOnWrite = true;
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(c.read(grabModeProvider).phase, ModePhase.notConfirmed);
      expect(c.read(grabModeProvider).message, contains('KHÔNG XÁC NHẬN'));
    });

    test('đọc lại thất bại sau khi ghi → notConfirmed (không báo thành công)', () async {
      final g = _FakeTransport(primary: 0);
      g.onWrite = () => g.readFails = true;
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(c.read(grabModeProvider).phase, ModePhase.notConfirmed);
      expect(c.read(grabModeProvider).on, isNull);
    });

    test('mất kết nối sau khi ghi → notConfirmed, không đọc lại', () async {
      final g = _FakeTransport(primary: 0);
      var connected = true;
      g.onWrite = () => connected = false;
      final c = _container(
        grab: g,
        link: () => RegenLinkInfo(
            connected: connected, authorized: connected, telemetryFresh: true, speedKmh: 0),
      );
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(c.read(grabModeProvider).phase, ModePhase.notConfirmed);
      expect(g.reads, 0);
      expect(g.writes, 1);
    });

    test('xe đang chạy → bị chặn, không ghi', () async {
      final g = _FakeTransport(primary: 0);
      final c = _container(
        grab: g,
        link: () => const RegenLinkInfo(
            connected: true, authorized: true, telemetryFresh: true, speedKmh: 20),
      );
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(g.writes, 0);
      expect(c.read(grabModeProvider).phase, ModePhase.blocked);
    });

    test('telemetry cũ hoặc chưa biết tốc độ → bị chặn, không ghi', () async {
      for (final link in [
        const RegenLinkInfo(
            connected: true, authorized: true, telemetryFresh: false, speedKmh: 0),
        const RegenLinkInfo(
            connected: true, authorized: true, telemetryFresh: true, speedKmh: null),
      ]) {
        final g = _FakeTransport(primary: 0);
        final c = _container(grab: g, link: () => link);
        addTearDown(c.dispose);
        await c.read(grabModeProvider.notifier).command(true);
        expect(g.writes, 0);
        expect(c.read(grabModeProvider).phase, ModePhase.blocked);
      }
    });

    test('chưa kết nối → không gửi lệnh', () async {
      final g = _FakeTransport(primary: 0);
      final c = _container(
        grab: g,
        link: () => const RegenLinkInfo(
            connected: false, authorized: false, telemetryFresh: false, speedKmh: null),
      );
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(g.writes, 0);
    });

    test('chống lệnh lặp: lệnh thứ hai trong thời gian nguội bị chặn', () async {
      final g = _FakeTransport(primary: 0);
      final c = _container(grab: g, cooldown: const Duration(seconds: 30));
      addTearDown(c.dispose);
      final n = c.read(grabModeProvider.notifier);
      await n.command(true);
      await n.command(false);
      expect(g.writes, 1);
      expect(c.read(grabModeProvider).phase, ModePhase.blocked);
    });

    test('giá trị thô lạ (2) không được diễn giải thành bật/tắt', () async {
      final g = _FakeTransport(primary: 2);
      final c = _container(grab: g);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).sync();
      expect(c.read(grabModeProvider).on, isNull);
      expect(c.read(grabModeProvider).message, contains('không phải 0/1'));
    });
  });

  group('ECE', () {
    test('BẬT: cần CẢ HAI cờ đọc lại = 1 mới confirmed', () async {
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      final c = _container(grab: _FakeTransport(primary: 0), ece: e);
      addTearDown(c.dispose);
      await c.read(eceModeProvider.notifier).command(true);
      expect(c.read(eceModeProvider).phase, ModePhase.confirmed);
      expect(c.read(eceModeProvider).snapshot?.secondaryRaw, 1);
    });

    test('cờ SpeedLimit không đổi → KHÔNG XÁC NHẬN dù ECE đã = 1', () async {
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true)..secondaryApply = false;
      final c = _container(grab: _FakeTransport(primary: 0), ece: e);
      addTearDown(c.dispose);
      await c.read(eceModeProvider.notifier).command(true);
      expect(c.read(eceModeProvider).phase, ModePhase.notConfirmed);
    });

    test('ghi một phần → báo rõ, không thử lại', () async {
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true)..partialFail = true;
      final c = _container(grab: _FakeTransport(primary: 0), ece: e);
      addTearDown(c.dispose);
      await c.read(eceModeProvider.notifier).command(true);
      expect(c.read(eceModeProvider).phase, ModePhase.notConfirmed);
      expect(c.read(eceModeProvider).message, contains('Một phần'));
      expect(e.writes, 1);
    });

    test('TẮT thủ công → confirmed khi cả hai về 0', () async {
      final e = _FakeTransport(primary: 1, secondary: 1, pair: true);
      final c = _container(grab: _FakeTransport(primary: 0), ece: e);
      addTearDown(c.dispose);
      await c.read(eceModeProvider.notifier).command(false);
      expect(c.read(eceModeProvider).phase, ModePhase.confirmed);
      expect(c.read(eceModeProvider).on, isFalse);
    });

    test('xe đang chạy → bị chặn, không ghi', () async {
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      final c = _container(
        grab: _FakeTransport(primary: 0),
        ece: e,
        link: () => const RegenLinkInfo(
            connected: true, authorized: true, telemetryFresh: true, speedKmh: 35),
      );
      addTearDown(c.dispose);
      await c.read(eceModeProvider.notifier).command(true);
      expect(e.writes, 0);
    });
  });

  group('Ba chế độ không tác động nhầm lên nhau', () {
    test('lệnh Grab không chạm transport ECE và ngược lại', () async {
      final g = _FakeTransport(primary: 0);
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      final c = _container(grab: g, ece: e);
      addTearDown(c.dispose);
      await c.read(grabModeProvider.notifier).command(true);
      expect(e.writes, 0);
      expect(e.reads, 0);
      await c.read(eceModeProvider.notifier).command(true);
      expect(g.writes, 1); // vẫn đúng 1 lệnh Grab từ trước
      expect(c.read(grabModeProvider).on, isTrue);
      expect(c.read(eceModeProvider).on, isTrue);
    });

    test('Regen độc lập bị khóa: không có đường ghi nào', () async {
      final c = ProviderContainer(overrides: [
        bleProvider.overrideWith(() => _FakeBle(const BleState(phase: BlePhase.connected))),
        regenLinkReaderProvider.overrideWithValue(() => _stopped),
      ]);
      addTearDown(c.dispose);
      await c.read(regenProvider.notifier).apply();
      expect(c.read(regenProvider).status, RegenSyncStatus.unsupported);
      expect(await c.read(regenTransportProvider).writeRaw(1), isFalse);
    });
  });

  group('Regen — số liệu chỉ đọc', () {
    test('không suy công suất khi thiếu dữ liệu hoặc điện áp không hợp lệ', () {
      expect(regenReadingFrom(null), isNull);
      expect(regenReadingFrom(BikeLogMsg()..voltage = 0..phase = 10), isNull);
    });

    test('công suất = V × I / 1000, giữ nguyên dấu', () {
      final r = regenReadingFrom(BikeLogMsg()
        ..voltage = 72
        ..phase = -10
        ..speed = 18)!;
      expect(r.powerKw, closeTo(-0.72, 1e-9));
      expect(r.phaseCurrentA, -10);
      expect(r.speedKmh, 18);
    });
  });

  group('Giao diện Trung tâm điều khiển', () {
    Widget host(_FakeTransport g, _FakeTransport e, {BlePhase phase = BlePhase.connected}) {
      return ProviderScope(
        overrides: [
          bleProvider.overrideWith(
              () => _FakeBle(BleState(phase: phase, isAuthorized: phase == BlePhase.connected))),
          grabTransportProvider.overrideWithValue(g),
          eceTransportProvider.overrideWithValue(e),
          modeReadbackDelayProvider.overrideWithValue(Duration.zero),
          modeCooldownProvider.overrideWithValue(Duration.zero),
          regenLinkReaderProvider.overrideWithValue(() => phase == BlePhase.connected
              ? _stopped
              : const RegenLinkInfo(
                  connected: false, authorized: false, telemetryFresh: false, speedKmh: null)),
        ],
        child: const MaterialApp(home: ControlCenterScreen()),
      );
    }

    void narrow(WidgetTester tester) {
      tester.view.physicalSize = const Size(320 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    testWidgets('ba thẻ riêng; chỉ Grab và ECE có công tắc; Regen không có', (tester) async {
      narrow(tester);
      final g = _FakeTransport(primary: 0);
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      await tester.pumpWidget(host(g, e));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('grab_card')), findsOneWidget);
      expect(find.byKey(const Key('ece_card')), findsOneWidget);
      expect(find.byKey(const Key('regen_monitor_card')), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.byKey(const Key('regen_unsupported_banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Mở màn hình chỉ ĐỌC, không ghi.
      expect(g.writes + e.writes, 0);
      expect(g.reads, greaterThan(0));
    });

    testWidgets('công tắc phản ánh giá trị đọc từ xe (không phải cache)', (tester) async {
      narrow(tester);
      final g = _FakeTransport(primary: 1);
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      await tester.pumpWidget(host(g, e));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<Switch>(find.byKey(const Key('grab_switch'))).value, isTrue);
      expect(tester.widget<Switch>(find.byKey(const Key('ece_switch'))).value, isFalse);
      expect(find.text('ĐANG BẬT'), findsOneWidget);
      expect(find.text('ĐANG TẮT'), findsOneWidget);
    });

    testWidgets('chưa kết nối: công tắc bị khóa, trạng thái "CHƯA KẾT NỐI"', (tester) async {
      narrow(tester);
      await tester.pumpWidget(host(
        _FakeTransport(primary: 0),
        _FakeTransport(primary: 0, secondary: 0, pair: true),
        phase: BlePhase.disconnected,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<Switch>(find.byKey(const Key('grab_switch'))).onChanged, isNull);
      expect(tester.widget<Switch>(find.byKey(const Key('ece_switch'))).onChanged, isNull);
      expect(find.text('CHƯA KẾT NỐI'), findsNWidgets(2));
    });

    testWidgets('gạt công tắc: phải qua hộp thoại xác nhận mới gửi lệnh', (tester) async {
      narrow(tester);
      final g = _FakeTransport(primary: 0);
      final e = _FakeTransport(primary: 0, secondary: 0, pair: true);
      await tester.pumpWidget(host(g, e));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const Key('grab_switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('confirm_ok')), findsOneWidget);
      expect(g.writes, 0); // chưa xác nhận → chưa gửi

      // HỦY → vẫn không gửi.
      await tester.tap(find.byKey(const Key('confirm_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.writes, 0);

      // Gạt lại rồi XÁC NHẬN → gửi đúng 1 lệnh và đọc lại.
      await tester.tap(find.byKey(const Key('grab_switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('confirm_ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.writes, 1);
      expect(e.writes, 0);
      expect(find.text('ĐÃ XÁC NHẬN · BẬT'), findsOneWidget);
    });
  });
}
