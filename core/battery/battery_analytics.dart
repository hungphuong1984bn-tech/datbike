// Battery Analytics Engine — phân tích gói BMS thành PackSnapshot.
// Thuần Dart, không phụ thuộc Flutter/BLE nên kiểm thử được độc lập.

import '../proto/bike_log.dart';
import 'battery_config.dart';
import 'cell_model.dart';

class BatteryAnalytics {
  BatteryAnalytics._();

  /// Dải điện áp vật lý hợp lệ của MỘT cell mà bộ giải mã gói BMS đã dùng
  /// (0 < V ≤ 6). Đây là kiểm tra tính hợp lệ của số liệu, KHÔNG phải ngưỡng
  /// hoá học của loại cell.
  static const double maxPlausibleCellV = 6.0;

  static bool isValidCellVoltage(double v) =>
      v.isFinite && v > 0.0 && v <= maxPlausibleCellV;

  /// ΔV (mV) giữa cell cao nhất và thấp nhất trong các cell hợp lệ.
  /// Trả về null nếu có ít hơn 2 cell hợp lệ.
  static double? deltaMv(Iterable<double> voltages) {
    double? hi;
    double? lo;
    var n = 0;
    for (final v in voltages) {
      if (!isValidCellVoltage(v)) continue;
      n++;
      if (hi == null || v > hi) hi = v;
      if (lo == null || v < lo) lo = v;
    }
    if (n < 2 || hi == null || lo == null) return null;
    return (hi - lo) * 1000.0;
  }

  /// Phân loại một cell theo cấu hình. Ngưỡng tuyệt đối chỉ được áp dụng khi
  /// người dùng đã cấu hình (khác null).
  static CellStatus classify({
    required double voltage,
    required double deviationMv,
    required bool useDeviation,
    required BatteryConfig cfg,
  }) {
    if (!isValidCellVoltage(voltage)) return CellStatus.invalid;

    final ovCrit = cfg.cellOverVoltCritV;
    final uvCrit = cfg.cellUnderVoltCritV;
    if ((ovCrit != null && voltage >= ovCrit) ||
        (uvCrit != null && voltage <= uvCrit)) {
      return CellStatus.critical;
    }
    if (useDeviation && deviationMv.abs() >= cfg.cellDeviationCritMv) {
      return CellStatus.critical;
    }

    final ovWarn = cfg.cellOverVoltWarnV;
    final uvWarn = cfg.cellUnderVoltWarnV;
    if ((ovWarn != null && voltage >= ovWarn) ||
        (uvWarn != null && voltage <= uvWarn)) {
      return CellStatus.warning;
    }
    if (useDeviation && deviationMv.abs() >= cfg.cellDeviationWarnMv) {
      return CellStatus.warning;
    }
    return CellStatus.ok;
  }

  static PackSnapshot analyze(
    BatteryLogMsg msg,
    DateTime receivedAt, {
    BatteryConfig cfg = BatteryConfig.defaults,
  }) {
    final volts = msg.cellVols;

    var validCount = 0;
    var sum = 0.0;
    var hi = 0.0;
    var lo = 0.0;
    var hiIdx = -1;
    var loIdx = -1;
    for (var i = 0; i < volts.length; i++) {
      final v = volts[i];
      if (!isValidCellVoltage(v)) continue;
      sum += v;
      if (validCount == 0) {
        hi = v;
        lo = v;
        hiIdx = i;
        loIdx = i;
      } else {
        if (v > hi) {
          hi = v;
          hiIdx = i;
        }
        if (v < lo) {
          lo = v;
          loIdx = i;
        }
      }
      validCount++;
    }

    final avg = validCount > 0 ? sum / validCount : 0.0;
    final delta = validCount >= 2 ? (hi - lo) * 1000.0 : 0.0;
    final flagExtremes = validCount >= 2 && delta > 0.0;
    final useDeviation = validCount >= 3;

    final cells = List<CellSnapshot>.generate(volts.length, (i) {
      final v = volts[i];
      final ok = isValidCellVoltage(v);
      final dev = ok && validCount > 0 ? (v - avg) * 1000.0 : 0.0;
      return CellSnapshot(
        index: i,
        voltage: ok ? v : 0.0,
        valid: ok,
        deviationMv: dev,
        status: classify(
          voltage: v,
          deviationMv: dev,
          useDeviation: useDeviation,
          cfg: cfg,
        ),
        isMax: flagExtremes && i == hiIdx,
        isMin: flagExtremes && i == loIdx,
      );
    }, growable: false);

    return PackSnapshot(
      receivedAt: receivedAt,
      cells: cells,
      validCount: validCount,
      vMax: validCount > 0 ? hi : 0.0,
      vMin: validCount > 0 ? lo : 0.0,
      vAvg: avg,
      maxIndex: hiIdx,
      minIndex: loIdx,
      deltaMv: delta,
      sumCellsV: sum,
      packVoltage: msg.voltage.isFinite ? msg.voltage : 0.0,
      current: msg.current.isFinite ? msg.current : 0.0,
      chargeFlag: msg.charge,
      dischargeFlag: msg.discharge,
      balancingRaw: msg.balancing,
      protectionRaw: msg.protection,
      protections: List<int>.unmodifiable(msg.protections),
      errorCode: msg.error,
      ntcs: List<double>.unmodifiable(msg.ntcs),
      resistorMo: msg.resistor.isFinite ? msg.resistor : 0.0,
      fetTemp: msg.fet.isFinite ? msg.fet : 0.0,
      socPercent: msg.socSoc.isFinite ? msg.socSoc : 0.0,
      cycles: msg.socCycles.isFinite ? msg.socCycles : 0.0,
    );
  }
}
