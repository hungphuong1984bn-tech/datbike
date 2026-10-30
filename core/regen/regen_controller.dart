// Bộ điều khiển Regen: chọn mức → qua cổng an toàn → ghi → ĐỌC LẠI → so khớp.
// Không bao giờ báo thành công nếu chưa đọc lại được đúng mức từ xe.
// Không chạm tới phanh cơ, ga, giới hạn công suất hay chức năng an toàn khác.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_controller.dart';
import '../ble/ble_logger.dart';
import 'regen_protocol.dart';

/// Mức Grab cao nhất mà bước dò đã chứng minh xe ghi + đọc lại đúng.
/// Mặc định 1 (chỉ 0/1 — đã xác minh). Lưu cục bộ trên điện thoại.
final grabMaxLevelProvider =
    NotifierProvider<GrabMaxLevelNotifier, int>(GrabMaxLevelNotifier.new);

class GrabMaxLevelNotifier extends Notifier<int> {
  static const _key = 'regen_grab_max_level';

  @override
  int build() {
    _load();
    return 1;
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getInt(_key);
      if (v != null && v >= 1 && v <= 9) state = v;
    } catch (_) {}
  }

  Future<void> set(int v) async {
    final nv = v < 1 ? 1 : (v > 9 ? 9 : v);
    state = nv;
    try {
      await (await SharedPreferences.getInstance()).setInt(_key, nv);
    } catch (_) {}
  }
}

/// Giao thức Regen hiện hành: Grab (a1d8e7c4), các mức đã xác minh.
final regenSpecProvider = Provider<RegenProtocolSpec>(
    (ref) => RegenProtocolSpec.grab(maxLevel: ref.watch(grabMaxLevelProvider)));

/// Đường tới xe: đọc/ghi char Grab qua BleController (protected write + đọc lại).
final regenTransportProvider =
    Provider<RegenTransport>((ref) => GrabRegenTransport(ref));

class GrabRegenTransport implements RegenTransport {
  final Ref _ref;
  GrabRegenTransport(this._ref);

  @override
  Future<int?> readRaw() => _ref.read(bleProvider.notifier).readGrabRaw();

  @override
  Future<bool> writeRaw(int raw) =>
      _ref.read(bleProvider.notifier).writeGrabLevelRaw(raw);
}

/// Thời gian chờ xe áp dụng trước khi đọc lại.
final regenReadbackDelayProvider =
    Provider<Duration>((ref) => const Duration(milliseconds: 400));

/// Hàm lấy tình trạng liên kết TẠI THỜI ĐIỂM GỌI (không cache), để kiểm tra
/// độ mới của telemetry đúng lúc bấm.
final regenLinkReaderProvider = Provider<RegenLinkInfo Function()>((ref) {
  return () {
    final s = ref.read(bleProvider);
    final n = ref.read(bleProvider.notifier);
    return RegenLinkInfo(
      connected: s.phase == BlePhase.connected,
      authorized: s.isAuthorized,
      telemetryFresh: n.telemetryFresh,
      speedKmh: s.lastTelemetry?.speed,
    );
  };
});

final regenProvider =
    NotifierProvider<RegenController, RegenState>(RegenController.new);

class RegenController extends Notifier<RegenState> {
  bool _busy = false;

  @override
  RegenState build() {
    final spec = ref.read(regenSpecProvider);
    if (!spec.verified) {
      return const RegenState(
        status: RegenSyncStatus.unsupported,
        message: 'Chưa xác minh giao thức Regen của xe nên chưa thể điều khiển.',
      );
    }
    return const RegenState(status: RegenSyncStatus.unknown);
  }

  void _log(String ev, [Map<String, Object?> extra = const {}]) =>
      BleLogger.instance.event('regen_$ev', extra);

  /// Đọc mức hiện tại từ xe. Không ghi gì.
  Future<void> refresh() async {
    final spec = ref.read(regenSpecProvider);
    if (!spec.verified) {
      state = state.copyWith(
        status: RegenSyncStatus.unsupported,
        message: 'Chưa xác minh giao thức Regen — không có gì để đọc.',
      );
      return;
    }
    final link = ref.read(regenLinkReaderProvider)();
    if (!link.connected || !link.authorized) {
      state = state.copyWith(
        status: RegenSyncStatus.disconnected,
        currentIndex: null,
        currentRaw: null,
        message: 'Chưa kết nối/xác thực xe — chưa đọc được mức Regen.',
      );
      return;
    }
    await _readBack(spec, expectIndex: null);
  }

  /// Chọn mức (chỉ chọn trên giao diện, CHƯA gửi).
  void select(int index) {
    final spec = ref.read(regenSpecProvider);
    if (!spec.verified || spec.levelByIndex(index) == null) return;
    if (_busy) return;
    final synced = state.currentIndex == index;
    state = state.copyWith(
      selectedIndex: index,
      status: synced ? RegenSyncStatus.synced : RegenSyncStatus.pending,
      message: synced ? 'Mức đã chọn trùng với mức hiện tại trên xe.' : null,
    );
  }

  void step(int delta) {
    final spec = ref.read(regenSpecProvider);
    if (!spec.verified || spec.levels.isEmpty) return;
    final base = state.selectedIndex ?? state.currentIndex;
    if (base == null) return; // chưa biết mức xe → không đoán
    final next = (base + delta).clamp(0, spec.levels.length - 1);
    select(next);
  }

  /// Gửi mức đã chọn xuống xe (qua cổng an toàn) rồi đọc lại xác nhận.
  Future<void> apply() async {
    if (_busy) return;
    final spec = ref.read(regenSpecProvider);
    if (!spec.verified) {
      state = state.copyWith(
        status: RegenSyncStatus.unsupported,
        message: 'Đã chặn: giao thức Regen chưa được xác minh. Không có lệnh nào được gửi.',
      );
      _log('apply_blocked_unverified');
      return;
    }
    final sel = state.selectedIndex;
    final level = sel == null ? null : spec.levelByIndex(sel);
    if (level == null) {
      state = state.copyWith(status: RegenSyncStatus.failed, message: 'Chưa chọn mức hợp lệ.');
      return;
    }
    final reason = regenBlockReason(
      ref.read(regenLinkReaderProvider)(),
      requiresStandstill: spec.requiresStandstill,
    );
    if (reason != null) {
      state = state.copyWith(status: RegenSyncStatus.failed, message: 'Không gửi: $reason');
      _log('apply_blocked_safety', {'reason': reason});
      return;
    }

    _busy = true;
    final transport = ref.read(regenTransportProvider);
    try {
      state = state.copyWith(status: RegenSyncStatus.writing, message: 'Đang gửi lệnh xuống xe…');
      _log('write', {'level': level.index, 'raw': level.rawValue});
      final accepted = await transport.writeRaw(level.rawValue);
      if (!accepted) {
        state = state.copyWith(
          status: RegenSyncStatus.failed,
          message: 'Xe từ chối hoặc không nhận lệnh. Mức Regen trên xe chưa được xác nhận thay đổi.',
        );
        return;
      }
      await Future<void>.delayed(ref.read(regenReadbackDelayProvider));
      // Mất kết nối giữa chừng → không báo thành công.
      final link = ref.read(regenLinkReaderProvider)();
      if (!link.connected) {
        state = state.copyWith(
          status: RegenSyncStatus.failed,
          currentIndex: null,
          currentRaw: null,
          message: 'Mất kết nối sau khi gửi lệnh — không xác nhận được mức Regen. Kết nối lại rồi bấm "Đọc lại từ xe".',
        );
        return;
      }
      await _readBack(spec, expectIndex: level.index);
    } catch (e) {
      _log('write_error', {'error': '$e'});
      state = state.copyWith(
        status: RegenSyncStatus.failed,
        message: 'Lỗi giao tiếp khi gửi lệnh: $e. Trạng thái trên xe chưa được xác nhận.',
      );
    } finally {
      _busy = false;
    }
  }

  /// DÒ CÓ KIỂM SOÁT: xem xe có ghi + đọc lại được mức Grab >= 2 không.
  /// - Chỉ chạy khi qua cổng an toàn (đứng yên, telemetry mới).
  /// - Dừng ngay ở mức đầu tiên xe không đọc lại đúng.
  /// - LUÔN khôi phục mức ban đầu rồi đọc lại xác nhận.
  /// - Kết quả chỉ nói "xe lưu được giá trị"; KHÔNG chứng minh hiệu ứng Regen.
  Future<void> probeHigherLevels({int maxCandidate = 4}) async {
    if (_busy) return;
    final spec = ref.read(regenSpecProvider);
    if (!spec.verified) return;
    final reason = regenBlockReason(
      ref.read(regenLinkReaderProvider)(),
      requiresStandstill: true,
    );
    if (reason != null) {
      state = state.copyWith(status: RegenSyncStatus.failed, message: 'Không dò: $reason');
      return;
    }
    _busy = true;
    final transport = ref.read(regenTransportProvider);
    final delay = ref.read(regenReadbackDelayProvider);
    int? original;
    var best = 1;
    String finding = '';
    try {
      state = state.copyWith(status: RegenSyncStatus.writing, message: 'Đang dò mức Regen cao hơn…');
      original = await transport.readRaw();
      if (original == null) {
        state = state.copyWith(
          status: RegenSyncStatus.failed,
          message: 'Không đọc được mức hiện tại nên dừng dò (không ghi gì).',
        );
        return;
      }
      for (var c = 2; c <= maxCandidate; c++) {
        if (!ref.read(regenLinkReaderProvider)().connected) {
          finding = 'Mất kết nối khi dò — dừng.';
          break;
        }
        _log('probe_write', {'raw': c});
        final ok = await transport.writeRaw(c);
        if (!ok) {
          finding = 'Xe từ chối ghi mức $c — dừng dò.';
          break;
        }
        await Future<void>.delayed(delay);
        final r = await transport.readRaw();
        _log('probe_readback', {'wrote': c, 'read': r});
        if (r == c) {
          best = c;
        } else {
          finding = 'Ghi mức $c nhưng xe đọc lại ${r ?? "không đọc được"} '
              '— firmware có vẻ không hỗ trợ mức này.';
          break;
        }
      }
    } catch (e) {
      finding = 'Lỗi giao tiếp khi dò: $e';
    } finally {
      // Luôn khôi phục mức ban đầu.
      String restore = '';
      if (original != null) {
        try {
          final ok = await transport.writeRaw(original);
          await Future<void>.delayed(delay);
          final r = await transport.readRaw();
          restore = (ok && r == original)
              ? 'Đã khôi phục mức ban đầu ($original) và đọc lại xác nhận.'
              : '⚠️ KHÔNG xác nhận được việc khôi phục mức ban đầu ($original), '
                  'xe đọc lại ${r ?? "không đọc được"}. Hãy đặt lại mức Regen thủ công rồi '
                  'tắt/bật nguồn xe.';
          _log('probe_restore', {'original': original, 'read': r, 'ok': ok});
        } catch (e) {
          restore = '⚠️ Lỗi khi khôi phục mức ban đầu ($original): $e. '
              'Đặt lại mức Regen thủ công rồi tắt/bật nguồn xe.';
        }
        if (best > ref.read(grabMaxLevelProvider)) {
          await ref.read(grabMaxLevelProvider.notifier).set(best);
        }
        state = state.copyWith(
          status: restore.startsWith('⚠️') ? RegenSyncStatus.failed : RegenSyncStatus.unknown,
          currentIndex: null,
          currentRaw: null,
          selectedIndex: null,
          message: [
            best >= 2
                ? 'Xe ghi và đọc lại được tới mức $best (hiệu ứng Regen các mức ≥ 2 CHƯA xác minh — hãy đo).'
                : 'Chỉ mức 0/1 được xác nhận.',
            if (finding.isNotEmpty) finding,
            restore,
          ].join('\n'),
        );
      }
      _busy = false;
    }
  }

  Future<void> _readBack(RegenProtocolSpec spec, {required int? expectIndex}) async {
    state = state.copyWith(status: RegenSyncStatus.verifying, message: 'Đang đọc lại từ xe…');
    int? raw;
    try {
      raw = await ref.read(regenTransportProvider).readRaw();
    } catch (e) {
      _log('read_error', {'error': '$e'});
      raw = null;
    }
    if (raw == null) {
      state = state.copyWith(
        status: expectIndex == null ? RegenSyncStatus.unknown : RegenSyncStatus.failed,
        currentIndex: null,
        currentRaw: null,
        message: 'Không đọc lại được mức Regen từ xe — chưa thể xác nhận.',
      );
      return;
    }
    final now = DateTime.now();
    final lvl = spec.levelByRaw(raw);
    if (lvl == null) {
      state = state.copyWith(
        status: RegenSyncStatus.mismatch,
        currentIndex: null,
        currentRaw: raw,
        lastReadAt: now,
        message: 'Xe báo giá trị thô $raw không thuộc mức nào đã xác minh.',
      );
      return;
    }
    if (expectIndex != null && lvl.index != expectIndex) {
      state = state.copyWith(
        status: RegenSyncStatus.mismatch,
        currentIndex: lvl.index,
        currentRaw: raw,
        lastReadAt: now,
        message: 'Chưa đồng bộ: xe đang ở "${lvl.label}", khác mức đã chọn.',
      );
      return;
    }
    state = state.copyWith(
      status: RegenSyncStatus.synced,
      currentIndex: lvl.index,
      currentRaw: raw,
      selectedIndex: expectIndex ?? lvl.index,
      lastReadAt: now,
      message: expectIndex == null
          ? 'Đã đọc mức hiện tại từ xe: ${lvl.label}.'
          : 'Đã xác nhận từ xe: ${lvl.label}.',
    );
  }
}
