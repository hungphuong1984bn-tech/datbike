// Nối telemetry xe (bleProvider, CHỈ ĐỌC) với OpsHistory. Không gửi lệnh nào.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../proto/bike_log.dart';
import 'ops_history.dart';

class OpsCenter extends Notifier<int> {
  final OpsHistory history = OpsHistory();
  bool _needsReset = false;

  @override
  int build() {
    ref.listen<BikeLogMsg?>(
      bleProvider.select((s) => s.lastTelemetry),
      (prev, next) => _onTelemetry(next),
    );
    ref.listen<BlePhase>(bleProvider.select((s) => s.phase), (prev, next) {
      // Mất kết nối: phiên sau là chuỗi mới, tránh nối hai đoạn bằng một đường thẳng.
      if (next != BlePhase.connected) _needsReset = true;
    });
    return 0;
  }

  void _onTelemetry(BikeLogMsg? t) {
    if (t == null) return;
    if (ref.read(bleProvider).phase != BlePhase.connected) return;
    if (_needsReset) {
      history.clear();
      _needsReset = false;
    }
    final at = ref.read(bleProvider.notifier).lastTelemetryAt ?? DateTime.now();
    final wrote = history.add(
      at: at,
      speedKmh: t.speed,
      voltageV: t.voltage,
      phaseAmps: t.phase,
      bmsC: t.bmsTemp,
      ecuC: t.ecu,
      motorC: t.motor,
    );
    if (wrote) state = state + 1;
  }
}

final opsProvider = NotifierProvider<OpsCenter, int>(OpsCenter.new);
