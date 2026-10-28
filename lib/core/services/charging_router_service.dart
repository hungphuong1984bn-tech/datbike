// Bộ Giám Sát & Phân Tích Thông Số Sạc Xe Điện Dat Bike
//
// 1. Nhận diện trạng thái sạc: Dòng điện DƯƠNG đi vào pack (telemetry.phase > +0.5A) hoặc gói tin ChargerLogMsg.
// 2. Tính toán công suất sạc thực tế: P = V_pack * I_nạp.
// 3. Bộ đếm thời gian thông minh Smart ETA: Ước lượng thời gian sạc tới mốc an toàn 80% và 100%.
// 4. Minh bạch thông số: Điện áp lưới Vin RMS & Nhiệt củ sạc chỉ hiển thị khi có dữ liệu từ trạm/bộ sạc thông minh.

import 'dart:math';
import '../proto/bike_log.dart';

class ChargingStatusReport {
  final bool isCharging;
  final String stageName;
  final int stage;
  final int powerWatts;
  final double? gridVoltageRms;
  final bool isGridUnstable;
  final int? fetTemp;
  final bool isFetOverheat;
  final Duration etaTotal;
  final Duration eta80;
  final Duration boostRemaining;
  final String profileName;
  final double energyChargedKwh;
  final int targetSocLimit;

  const ChargingStatusReport({
    required this.isCharging,
    required this.stageName,
    required this.stage,
    required this.powerWatts,
    required this.gridVoltageRms,
    required this.isGridUnstable,
    required this.fetTemp,
    required this.isFetOverheat,
    required this.etaTotal,
    required this.eta80,
    required this.boostRemaining,
    required this.profileName,
    required this.energyChargedKwh,
    this.targetSocLimit = 80,
  });
}

class ChargingRouterService {
  ChargingRouterService._();

  /// Phân tích dữ liệu sạc chi tiết từ ChargerLogMsg và Telemetry
  static ChargingStatusReport analyzeCharging({
    BikeLogMsg? telemetry,
    int targetLimit = 80,
  }) {
    final charger = telemetry?.charging;
    // QUY ƯỚC DẤU (verify session 20261022T212957): current@8 ÂM = xe DÙNG pin
    // (chạy xe tải lớn tới -24.9A, điện áp xả 76.8→76.4V); sạc vào pin là DƯƠNG.
    // isCharging = có gói ChargerLogMsg HOẶC dòng DƯƠNG > 0.5A.
    final isCharging = charger != null || (telemetry != null && telemetry.phase > 0.5);

    final power = charger?.power ??
        (isCharging && telemetry != null && telemetry.voltage > 0
            ? (telemetry.voltage * telemetry.phase.abs()).round()
            : 0);

    // Không fix cứng 220V hay 36°C — chỉ hiển thị khi nhận được dữ liệu telemetry từ trạm sạc thật
    final double? vin = (charger != null && charger.vinRms > 0) ? charger.vinRms.toDouble() : null;
    final isGridUnstable = vin != null && (vin < 190.0 || vin > 255.0);
    final int? fetTemp = (charger != null && charger.fetTemp > 0) ? charger.fetTemp : null;
    final isFetHot = fetTemp != null && fetTemp > 65;

    final stage = charger?.stage ?? (isCharging ? 2 : 0);
    final stageName = switch (stage) {
      0 => 'Chưa cắm sạc',
      1 => 'Khởi động nguồn sạc',
      2 => isCharging ? 'Đang nạp pin (Dòng nạp ${telemetry?.phase.abs().toStringAsFixed(1) ?? "--"}A)' : 'Sạc nhanh Boost',
      3 => 'Sạc bảo vệ (Điện áp không đổi CV)',
      4 => 'Đã sạc đầy 100% (Trickle)',
      5 => 'Ngắt an toàn / Lỗi sạc',
      _ => 'Đang sạc',
    };

    final profileName = switch (charger?.profile ?? 0) {
      1 => 'Dat Charge Siêu Tốc (SuperBoost 4kW)',
      2 => 'Sạc chậm bảo vệ pin (Eco Night)',
      _ => isCharging ? 'Bộ sạc tiêu chuẩn AC' : 'Chưa sạc',
    };

    final currentPercent = telemetry?.percent ?? 0;
    final totalEtaSec = charger?.etaSec ?? _estimateEtaSeconds(currentPercent, 100, power);
    final eta80Sec = _estimateEtaSeconds(currentPercent, targetLimit, power);
    final boostSec = charger?.boostLeftSec ?? 0;

    // Ước tính kWh đã nạp
    final energyKwh = (power > 0 && charger != null)
        ? (power * charger.stageSec) / 3600000.0
        : 0.0;

    return ChargingStatusReport(
      isCharging: isCharging,
      stageName: stageName,
      stage: stage,
      powerWatts: power,
      gridVoltageRms: vin,
      isGridUnstable: isGridUnstable,
      fetTemp: fetTemp,
      isFetOverheat: isFetHot,
      etaTotal: Duration(seconds: max(0, totalEtaSec)),
      eta80: Duration(seconds: max(0, eta80Sec)),
      boostRemaining: Duration(seconds: max(0, boostSec)),
      profileName: profileName,
      energyChargedKwh: energyKwh,
      targetSocLimit: targetLimit,
    );
  }

  static int _estimateEtaSeconds(int currentPct, int targetPct, int powerWatts) {
    if (currentPct >= targetPct) return 0;
    // Pack pin Dat Bike Quantum: ~7.2 kWh (7200 Wh), Weaver++: ~5.0 kWh (5000 Wh)
    // Giả định pack chuẩn 7.0 kWh = 7000 Wh. 1% = 70 Wh.
    final pwr = powerWatts > 200 ? powerWatts : 1200;
    final neededPct = targetPct - currentPct;
    final neededWh = neededPct * 70.0;
    // Hiệu suất sạc ~92%
    final hours = (neededWh / (pwr * 0.92));
    return (hours * 3600).round();
  }
}
