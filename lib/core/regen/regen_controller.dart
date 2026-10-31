// Bộ điều khiển Regen: chọn mức → qua cổng an toàn → ghi → ĐỌC LẠI → so khớp.
// Không bao giờ báo thành công nếu chưa đọc lại được đúng mức từ xe.
// Không chạm tới phanh cơ, ga, giới hạn công suất hay chức năng an toàn khác.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../ble/ble_logger.dart';
import 'regen_protocol.dart';

/// Giao thức Regen hiện hành: CHƯA xác minh characteristic Regen độc lập nào.
/// (Char Grab a1d8e7c4 được điều khiển riêng ở lib/core/control — ở đó nó là
/// "Grab", không phải "mức Regen".) Vì vậy mô-đun này KHÓA mọi thao tác ghi.
/// Khi có bằng chứng (docs/REGEN_VERIFICATION.md §3), thay provider này bằng
/// RegenProtocolSpec(verified: true, ...) và cung cấp RegenTransport thật.
final regenSpecProvider =
    Provider<RegenProtocolSpec>((ref) => RegenProtocolSpec.unverified);

/// Không có đường tới xe cho Regen độc lập.
final regenTransportProvider =
    Provider<RegenTransport>((ref) => const UnavailableRegenTransport());

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
