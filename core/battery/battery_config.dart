// Cấu hình ngưỡng giám sát pin (Battery Cell Protection Center).
//
// NGUYÊN TẮC: ứng dụng KHÔNG biết loại cell hoá học và thông số nhà sản xuất của
// bộ pin, nên các ngưỡng điện áp tuyệt đối theo cell (quá áp / thấp áp) mặc định
// là `null` = TẮT cho tới khi người dùng nhập theo thông số BMS thực tế.
// Các ngưỡng còn lại (chênh lệch, nhiệt độ, đồng bộ dữ liệu) là mặc định của ứng
// dụng — không phải thông số nhà sản xuất — và chỉnh được.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BatteryConfig {
  /// Ngưỡng điện áp tuyệt đối từng cell (V). null = chưa cấu hình → không kiểm tra.
  final double? cellOverVoltWarnV;
  final double? cellOverVoltCritV;
  final double? cellUnderVoltWarnV;
  final double? cellUnderVoltCritV;

  /// Chênh lệch điện áp giữa cell cao nhất và thấp nhất (mV).
  final double deltaWarnMv;
  final double deltaCritMv;

  /// Độ lệch của một cell so với điện áp trung bình các cell hợp lệ (mV).
  final double cellDeviationWarnMv;
  final double cellDeviationCritMv;

  /// Nhiệt độ (°C) áp dụng cho cảm biến NTC pack và nhiệt độ BMS.
  final double tempWarnC;
  final double tempCritC;

  /// Chênh lệch tối đa giữa các NTC (°C) trước khi cảnh báo.
  final double ntcSpreadWarnC;

  /// Sai lệch cho phép giữa tổng điện áp cell và điện áp pack BMS báo (%).
  final double packSyncTolerancePct;

  /// Quá thời gian này không có gói BMS mới (khi đang kết nối) → cảnh báo mất dữ liệu.
  final int dataTimeoutSec;

  /// Số mẫu tối thiểu để đánh giá xu hướng suy giảm một cell.
  final int trendMinSamples;

  const BatteryConfig({
    this.cellOverVoltWarnV,
    this.cellOverVoltCritV,
    this.cellUnderVoltWarnV,
    this.cellUnderVoltCritV,
    this.deltaWarnMv = 80,
    this.deltaCritMv = 120,
    this.cellDeviationWarnMv = 40,
    this.cellDeviationCritMv = 60,
    this.tempWarnC = 48,
    this.tempCritC = 58,
    this.ntcSpreadWarnC = 10,
    this.packSyncTolerancePct = 3,
    this.dataTimeoutSec = 15,
    this.trendMinSamples = 60,
  });

  static const BatteryConfig defaults = BatteryConfig();

  bool get hasAbsoluteVoltageLimits =>
      cellOverVoltWarnV != null ||
      cellOverVoltCritV != null ||
      cellUnderVoltWarnV != null ||
      cellUnderVoltCritV != null;

  Map<String, dynamic> toJson() => {
        'ovWarn': cellOverVoltWarnV,
        'ovCrit': cellOverVoltCritV,
        'uvWarn': cellUnderVoltWarnV,
        'uvCrit': cellUnderVoltCritV,
        'deltaWarn': deltaWarnMv,
        'deltaCrit': deltaCritMv,
        'devWarn': cellDeviationWarnMv,
        'devCrit': cellDeviationCritMv,
        'tempWarn': tempWarnC,
        'tempCrit': tempCritC,
        'ntcSpread': ntcSpreadWarnC,
        'syncPct': packSyncTolerancePct,
        'timeoutSec': dataTimeoutSec,
        'trendMin': trendMinSamples,
      };

  factory BatteryConfig.fromJson(Map<String, dynamic> m) {
    double? opt(String k) {
      final v = m[k];
      if (v is num && v.isFinite) return v.toDouble();
      return null;
    }

    double req(String k, double d) => opt(k) ?? d;

    const d = BatteryConfig.defaults;
    return BatteryConfig(
      cellOverVoltWarnV: opt('ovWarn'),
      cellOverVoltCritV: opt('ovCrit'),
      cellUnderVoltWarnV: opt('uvWarn'),
      cellUnderVoltCritV: opt('uvCrit'),
      deltaWarnMv: req('deltaWarn', d.deltaWarnMv),
      deltaCritMv: req('deltaCrit', d.deltaCritMv),
      cellDeviationWarnMv: req('devWarn', d.cellDeviationWarnMv),
      cellDeviationCritMv: req('devCrit', d.cellDeviationCritMv),
      tempWarnC: req('tempWarn', d.tempWarnC),
      tempCritC: req('tempCrit', d.tempCritC),
      ntcSpreadWarnC: req('ntcSpread', d.ntcSpreadWarnC),
      packSyncTolerancePct: req('syncPct', d.packSyncTolerancePct),
      dataTimeoutSec: (opt('timeoutSec') ?? d.dataTimeoutSec.toDouble()).round().clamp(3, 600),
      trendMinSamples: (opt('trendMin') ?? d.trendMinSamples.toDouble()).round().clamp(10, 1000),
    );
  }

  /// Kiểm tra cấu hình do người dùng nhập có hợp lý không. Trả về thông báo lỗi
  /// tiếng Việt hoặc null nếu hợp lệ.
  String? validate() {
    if (cellOverVoltWarnV != null &&
        cellOverVoltCritV != null &&
        cellOverVoltCritV! < cellOverVoltWarnV!) {
      return 'Ngưỡng quá áp CRITICAL phải ≥ ngưỡng WARNING.';
    }
    if (cellUnderVoltWarnV != null &&
        cellUnderVoltCritV != null &&
        cellUnderVoltCritV! > cellUnderVoltWarnV!) {
      return 'Ngưỡng thấp áp CRITICAL phải ≤ ngưỡng WARNING.';
    }
    if (deltaCritMv < deltaWarnMv) return 'ΔV CRITICAL phải ≥ ΔV WARNING.';
    if (cellDeviationCritMv < cellDeviationWarnMv) {
      return 'Độ lệch cell CRITICAL phải ≥ WARNING.';
    }
    if (tempCritC < tempWarnC) return 'Nhiệt độ CRITICAL phải ≥ WARNING.';
    return null;
  }
}

/// Lưu / đọc cấu hình bằng SharedPreferences (đã là dependency của dự án).
class BatteryConfigStore {
  BatteryConfigStore._();
  static const _key = 'bms_config_v1';

  static Future<BatteryConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return BatteryConfig.defaults;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return BatteryConfig.defaults;
      final cfg = BatteryConfig.fromJson(decoded);
      return cfg.validate() == null ? cfg : BatteryConfig.defaults;
    } catch (_) {
      return BatteryConfig.defaults;
    }
  }

  static Future<void> save(BatteryConfig cfg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(cfg.toJson()));
    } catch (_) {
      // Lưu cấu hình thất bại không được ảnh hưởng luồng BLE/giám sát.
    }
  }

  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
