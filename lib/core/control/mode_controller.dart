// Bộ điều khiển chế độ vận hành BẬT/TẮT: Grab và ECE.
//
// QUY TẮC CỐT LÕI (docs/CONTROL_CENTER.md):
//  1. Chỉ gửi lệnh khi người dùng bấm (không có đường tự động nào gọi command()).
//  2. Trước khi gửi: đã kết nối + xác thực + xe đứng yên + telemetry < 4 giây.
//  3. Sau khi gửi: ĐỌC LẠI từ xe; chỉ "confirmed" khi đọc lại khớp.
//  4. KHÔNG tự thử lại. Không nhận được xác nhận → "notConfirmed".
//  5. Chống lệnh lặp: một lệnh tại một thời điểm + thời gian nguội giữa 2 lệnh.
//  6. Mỗi lệnh có id truy vết, ghi vào BleLogger (mode_cmd_*).
//  7. Hai chế độ không dùng chung characteristic ghi: Grab = a1d8e7c4,
//     ECE = {0a19a49a, 3b56ac38}. Regen KHÔNG ghi bất kỳ characteristic nào.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../ble/ble_logger.dart';
import '../ble/gatt.dart';
import '../regen/regen_controller.dart' show regenLinkReaderProvider;
import '../regen/regen_protocol.dart' show regenBlockReason;
import 'mode_types.dart';

// ─────────────────────────────────────────────────────────────────────────
// SPEC
// ─────────────────────────────────────────────────────────────────────────

/// Grab (a1d8e7c4). Mức 0/1.
/// Bằng chứng: Ghidra onWriteGrabMode @0x40153e30 (parser boolean) + Lab
/// 23/10 (ghi '1' đọc lại 01, ghi '0' đọc lại 00).
/// Lưu ý: người dùng quan sát 28/10 rằng đổi char này làm đổi dòng nạp ngược.
/// Hướng/độ lớn CHƯA đo — nên app không khẳng định mạnh hơn hay yếu hơn.
class GrabModeSpec extends ModeSpec {
  const GrabModeSpec();

  @override
  ModeKind get kind => ModeKind.grab;
  @override
  bool get verified => true;
  @override
  bool get requiresStandstill => true;
  @override
  String get evidence =>
      'a1d8e7c4: parser boolean (Ghidra onWriteGrabMode) + Lab 23/10 ghi/đọc lại 0/1. '
      'Không có bằng chứng về nhiều mức.';

  @override
  bool? interpret(ModeSnapshot s) {
    final v = s.primaryRaw;
    if (v == 1) return true;
    if (v == 0) return false;
    return null; // null hoặc giá trị lạ → KHÔNG đoán
  }
}

/// ECE. Cặp characteristic: ECE_MODE (3b56ac38) là "cổng"; SPEED_LIMIT
/// (0a19a49a) chỉ có hiệu lực khi ECE = 1 (Lab 24/10 PASS ×3).
/// Chế độ "đang giới hạn" = ECE=1 VÀ SpeedLimit=1.
/// Con số 60 km/h: lấy từ ghi chú dự án; docs/lab chỉ ghi "~60", CHƯA có số đo.
class EceModeSpec extends ModeSpec {
  const EceModeSpec();

  @override
  ModeKind get kind => ModeKind.ece;
  @override
  bool get verified => true;
  @override
  bool get requiresStandstill => true;
  @override
  String get evidence =>
      '3b56ac38 (onWriteEceMode @0x40153bd0) + 0a19a49a: Lab 24/10 PASS — ECE là cổng, '
      'SpeedLimit chỉ hiệu lực khi ECE=1. Mức trần 60 km/h chưa có số đo độc lập.';

  /// Trạng thái ECE = giá trị cờ ECE.
  @override
  bool? interpret(ModeSnapshot s) {
    final v = s.primaryRaw;
    if (v == 1) return true;
    if (v == 0) return false;
    return null;
  }

  /// Giới hạn tốc độ CÓ HIỆU LỰC khi cả hai cờ = 1.
  bool? limitEffective(ModeSnapshot s) {
    final e = s.primaryRaw;
    final l = s.secondaryRaw;
    if (e == null || l == null) return null;
    return e == 1 && l == 1;
  }

  /// ON chỉ khớp khi CẢ HAI cờ = 1; OFF chỉ khớp khi CẢ HAI = 0.
  @override
  bool matches(ModeSnapshot s, bool target) {
    final want = target ? 1 : 0;
    return s.primaryRaw == want && s.secondaryRaw == want;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TRANSPORT BLE
// ─────────────────────────────────────────────────────────────────────────

class GrabBleTransport implements ModeTransport {
  GrabBleTransport(this._ref);
  final Ref _ref;

  @override
  Future<ModeSnapshot> read() async {
    final dec = await _ref
        .read(bleProvider.notifier)
        .readFwSettingRaw(Gatt.grabModeChar, 'Grab');
    return ModeSnapshot(primaryRaw: dec.isEmpty ? null : dec[0]);
  }

  @override
  Future<ModeWriteResult> write(bool on, String cmdId) async {
    final o = await _ref
        .read(bleProvider.notifier)
        .writeBoolSettingVerified(Gatt.grabModeChar, on, 'Grab', cmdId: cmdId);
    return ModeWriteResult(sent: o.sent, error: o.error);
  }
}

class EceBleTransport implements ModeTransport {
  EceBleTransport(this._ref);
  final Ref _ref;

  @override
  Future<ModeSnapshot> read() async {
    final ble = _ref.read(bleProvider.notifier);
    final ece = await ble.readFwSettingRaw(Gatt.eceModeChar, 'ECE');
    final lim = await ble.readFwSettingRaw(Gatt.speedLimitChar, 'SpeedLimit');
    return ModeSnapshot(
      primaryRaw: ece.isEmpty ? null : ece[0],
      secondaryRaw: lim.isEmpty ? null : lim[0],
    );
  }

  /// Thứ tự ghi giữ đúng cơ chế đã Lab 24/10: SpeedLimit rồi ECE.
  /// Nếu char đầu lỗi thì KHÔNG ghi char sau (tránh trạng thái nửa vời).
  @override
  Future<ModeWriteResult> write(bool on, String cmdId) async {
    final ble = _ref.read(bleProvider.notifier);
    final a = await ble.writeBoolSettingVerified(Gatt.speedLimitChar, on, 'SpeedLimit',
        cmdId: cmdId);
    if (!a.sent) {
      return ModeWriteResult(sent: false, error: a.error ?? 'Ghi SpeedLimit thất bại.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final b = await ble.writeBoolSettingVerified(Gatt.eceModeChar, on, 'ECE', cmdId: cmdId);
    if (!b.sent) {
      return ModeWriteResult(
        sent: false,
        partial: true,
        error: 'Đã ghi SpeedLimit nhưng ghi ECE thất bại: ${b.error ?? "lỗi không rõ"}.',
      );
    }
    return const ModeWriteResult(sent: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────

final grabTransportProvider = Provider<ModeTransport>((ref) => GrabBleTransport(ref));
final eceTransportProvider = Provider<ModeTransport>((ref) => EceBleTransport(ref));

/// Thời gian chờ xe áp dụng trước khi đọc lại.
final modeReadbackDelayProvider =
    Provider<Duration>((ref) => const Duration(milliseconds: 400));

/// Thời gian nguội tối thiểu giữa hai lệnh GHI của cùng một chế độ.
final modeCooldownProvider = Provider<Duration>((ref) => const Duration(seconds: 3));

final grabModeProvider =
    NotifierProvider<GrabModeController, ModeState>(GrabModeController.new);
final eceModeProvider =
    NotifierProvider<EceModeController, ModeState>(EceModeController.new);

// ─────────────────────────────────────────────────────────────────────────
// CONTROLLER CHUNG
// ─────────────────────────────────────────────────────────────────────────

int _cmdSeq = 0;

abstract class ModeController extends Notifier<ModeState> {
  ModeSpec get spec;
  ModeTransport get transport;
  String get logName; // 'grab' | 'ece'

  bool _busy = false;
  DateTime? _lastWriteAt;

  @override
  ModeState build() {
    // Mất/khôi phục kết nối: CHỈ cập nhật hiển thị. Không bao giờ gửi lệnh.
    ref.listen<BlePhase>(bleProvider.select((s) => s.phase), (prev, next) {
      if (next != BlePhase.connected) {
        if (_busy) return; // luồng lệnh đang chạy sẽ tự phát hiện mất kết nối
        state = ModeState(
          phase: ModePhase.disconnected,
          message: 'Chưa kết nối xe — không đọc/gửi lệnh được.',
          lastCommand: state.lastCommand,
        );
      } else if (prev != BlePhase.connected) {
        state = ModeState(
          phase: ModePhase.unread,
          message: 'Đã kết nối lại. Trạng thái chưa được đọc — bấm "Đồng bộ". '
              'Không có lệnh nào được gửi tự động.',
          lastCommand: state.lastCommand,
        );
      }
    });

    if (!spec.verified) {
      return const ModeState(
        phase: ModePhase.unverified,
        message: 'Chưa xác minh giao thức — không gửi lệnh xuống xe.',
      );
    }
    final connected = ref.read(bleProvider).phase == BlePhase.connected;
    return ModeState(
      phase: connected ? ModePhase.unread : ModePhase.disconnected,
      message: connected
          ? 'Chưa đọc trạng thái từ xe. Bấm "Đồng bộ".'
          : 'Chưa kết nối xe.',
    );
  }

  void _log(String ev, [Map<String, Object?> extra = const {}]) =>
      BleLogger.instance.event('mode_$ev', {'mode': logName, ...extra});

  String _newCmdId() => '$logName-${DateTime.now().millisecondsSinceEpoch}-${++_cmdSeq}';

  /// Đọc trạng thái từ xe. KHÔNG ghi gì.
  Future<void> sync() async {
    if (_busy) return;
    if (!spec.verified) return;
    final link = ref.read(regenLinkReaderProvider)();
    if (!link.connected || !link.authorized) {
      state = state.copyWith(
        phase: ModePhase.disconnected,
        on: null,
        snapshot: null,
        message: 'Chưa kết nối/xác thực xe — chưa đọc được trạng thái.',
      );
      return;
    }
    _busy = true;
    try {
      state = state.copyWith(phase: ModePhase.verifying, message: 'Đang đọc từ xe…');
      final snap = await transport.read();
      _log('read', {'primary': snap.primaryRaw, 'secondary': snap.secondaryRaw});
      _applySnapshot(snap, fromCommand: false);
    } catch (e) {
      _log('read_error', {'error': '$e'});
      state = state.copyWith(
        phase: ModePhase.unread,
        on: null,
        snapshot: null,
        message: 'Lỗi khi đọc từ xe: $e',
      );
    } finally {
      _busy = false;
    }
  }

  void _applySnapshot(ModeSnapshot snap, {required bool fromCommand}) {
    if (snap.isEmpty) {
      state = state.copyWith(
        phase: fromCommand ? ModePhase.notConfirmed : ModePhase.unread,
        on: null,
        snapshot: null,
        message: 'Không đọc được trạng thái từ xe.',
      );
      return;
    }
    final v = spec.interpret(snap);
    state = state.copyWith(
      phase: ModePhase.ready,
      on: v,
      snapshot: snap,
      lastReadAt: DateTime.now(),
      message: v == null
          ? 'Xe báo giá trị thô ${snap.primaryRaw} không phải 0/1 — không diễn giải.'
          : null,
    );
  }

  /// Gửi lệnh bật/tắt. CHỈ gọi từ thao tác của người dùng (sau hộp thoại xác nhận).
  Future<void> command(bool target) async {
    if (_busy) return;
    if (!spec.verified) {
      state = state.copyWith(
        phase: ModePhase.unverified,
        message: 'Đã chặn: giao thức chưa xác minh. Không có lệnh nào được gửi.',
      );
      _log('cmd_blocked_unverified');
      return;
    }
    final now = DateTime.now();
    final cool = ref.read(modeCooldownProvider);
    if (_lastWriteAt != null && now.difference(_lastWriteAt!) < cool) {
      state = state.copyWith(
        phase: ModePhase.blocked,
        message: 'Vừa gửi lệnh xong — chờ vài giây rồi bấm "Đồng bộ" để xem kết quả.',
      );
      _log('cmd_blocked_cooldown');
      return;
    }
    final reason = regenBlockReason(
      ref.read(regenLinkReaderProvider)(),
      requiresStandstill: spec.requiresStandstill,
    );
    if (reason != null) {
      state = state.copyWith(phase: ModePhase.blocked, message: 'Không gửi: $reason');
      _log('cmd_blocked_safety', {'reason': reason});
      return;
    }

    _busy = true;
    _lastWriteAt = now;
    final id = _newCmdId();
    var trace = CommandTrace(id: id, targetOn: target, startedAt: now);
    try {
      state = state.copyWith(
        phase: ModePhase.sending,
        message: 'Đang gửi lệnh xuống xe…',
        lastCommand: trace,
      );
      _log('cmd_start', {'id': id, 'target': target ? 1 : 0});

      final res = await transport.write(target, id);
      if (!res.sent) {
        trace = trace.finish('rejected');
        _log('cmd_rejected', {'id': id, 'partial': res.partial, 'error': res.error});
        state = state.copyWith(
          phase: ModePhase.notConfirmed,
          message: 'KHÔNG XÁC NHẬN: xe không nhận lệnh.'
              '${res.error == null ? "" : "\n${res.error}"}'
              '${res.partial ? "\nMột phần lệnh đã được ghi — bấm \"Đồng bộ\" để xem trạng thái thật của xe." : ""}',
          lastCommand: trace,
        );
        return;
      }

      await Future<void>.delayed(ref.read(modeReadbackDelayProvider));
      final link = ref.read(regenLinkReaderProvider)();
      if (!link.connected) {
        trace = trace.finish('not_confirmed');
        _log('cmd_not_confirmed', {'id': id, 'why': 'disconnected'});
        state = ModeState(
          phase: ModePhase.notConfirmed,
          message: 'KHÔNG XÁC NHẬN: mất kết nối sau khi gửi lệnh. Kết nối lại rồi bấm "Đồng bộ".',
          lastCommand: trace,
        );
        return;
      }

      state = state.copyWith(
          phase: ModePhase.verifying, message: 'Đang đọc lại từ xe để xác nhận…');
      final snap = await transport.read();
      final ok = !snap.isEmpty && spec.matches(snap, target);
      trace = trace.finish(ok ? 'confirmed' : 'not_confirmed', readBack: snap);
      _log(ok ? 'cmd_confirmed' : 'cmd_not_confirmed', {
        'id': id,
        'target': target ? 1 : 0,
        'primary': snap.primaryRaw,
        'secondary': snap.secondaryRaw,
      });
      state = ModeState(
        phase: ok ? ModePhase.confirmed : ModePhase.notConfirmed,
        on: snap.isEmpty ? null : spec.interpret(snap),
        snapshot: snap.isEmpty ? null : snap,
        lastReadAt: snap.isEmpty ? state.lastReadAt : DateTime.now(),
        lastCommand: trace,
        message: ok
            ? 'Đã xác nhận từ xe: ${target ? "BẬT" : "TẮT"}.'
            : (snap.isEmpty
                ? 'KHÔNG XÁC NHẬN: không đọc lại được trạng thái từ xe.'
                : 'KHÔNG XÁC NHẬN: xe đọc lại giá trị thô '
                    '${snap.primaryRaw}${snap.secondaryRaw == null ? "" : "/${snap.secondaryRaw}"} '
                    '— khác trạng thái mong muốn.'),
      );
    } catch (e) {
      trace = trace.finish('not_confirmed');
      _log('cmd_error', {'id': id, 'error': '$e'});
      state = state.copyWith(
        phase: ModePhase.notConfirmed,
        message: 'KHÔNG XÁC NHẬN: lỗi giao tiếp: $e',
        lastCommand: trace,
      );
    } finally {
      _busy = false;
    }
  }
}

class GrabModeController extends ModeController {
  @override
  ModeSpec get spec => const GrabModeSpec();
  @override
  ModeTransport get transport => ref.read(grabTransportProvider);
  @override
  String get logName => 'grab';
}

class EceModeController extends ModeController {
  @override
  ModeSpec get spec => const EceModeSpec();
  @override
  ModeTransport get transport => ref.read(eceTransportProvider);
  @override
  String get logName => 'ece';
}
