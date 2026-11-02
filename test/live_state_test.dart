// Test hàm thuần resolveLiveLevel (không cần BLE thật, không mô phỏng xe).
// Chỉ kiểm tra logic phân loại trạng thái hiển thị.

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_controller.dart' show BlePhase;
import 'package:mybike_app/ui/ds/live_state.dart';

void main() {
  final now = DateTime(2026, 11, 2, 12, 0, 0);

  LiveLevel level(BlePhase p, {DateTime? at}) =>
      resolveLiveLevel(phase: p, lastTelemetryAt: at, now: now);

  group('resolveLiveLevel', () {
    test('chưa/mất kết nối → disconnected, dù có khung cũ', () {
      expect(level(BlePhase.idle), LiveLevel.disconnected);
      expect(level(BlePhase.disconnected), LiveLevel.disconnected);
      expect(
        level(BlePhase.disconnected, at: now.subtract(const Duration(seconds: 1))),
        LiveLevel.disconnected,
      );
    });

    test('đang quét/kết nối/kết nối lại → connecting', () {
      expect(level(BlePhase.scanning), LiveLevel.connecting);
      expect(level(BlePhase.connecting), LiveLevel.connecting);
      expect(level(BlePhase.reconnecting), LiveLevel.connecting);
    });

    test('đã kết nối nhưng chưa có khung nào → waiting (không bịa số)', () {
      expect(level(BlePhase.connected), LiveLevel.waiting);
    });

    test('đã kết nối: ≤ 5 giây là live, quá hạn là stale', () {
      expect(
        level(BlePhase.connected, at: now.subtract(const Duration(seconds: 5))),
        LiveLevel.live,
      );
      expect(
        level(BlePhase.connected, at: now.subtract(const Duration(seconds: 6))),
        LiveLevel.stale,
      );
    });
  });
}
