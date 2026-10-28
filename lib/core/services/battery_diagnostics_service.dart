// Bác Sĩ Pin & Chẩn Đoán Lỗi OBD — Động cơ phân tích chuyên sâu cho xe Dat Bike.
//
// 1. Phân tích cell pin: Vmax, Vmin, Vavg, Delta V (mV), phân cấp cân bằng cell từ BMS thực tế.
// 2. Bản đồ nhiệt độ 3 điểm: Motor, Inverter/ECU, Battery Pack/BMS.
// 3. Hệ thống mã lỗi OBD: Giải mã chuẩn VESC mc_fault_code Enum từ ECU & giám sát phần cứng an toàn.

import 'dart:math';
import '../proto/bike_log.dart';

enum CellBalanceGrade {
  unknown('Chờ telemetry BMS', 'Chưa nhận được gói tin chi tiết điện áp từng cell từ BMS xe.'),
  excellent('Hoàn hảo', 'Độ lệch áp cực thấp, các cell đồng đều tuyệt đối.'),
  good('Tốt', 'Khối pin cân bằng tốt, hiệu suất xả nạp tối ưu.'),
  fair('Cần theo dõi', 'Có độ lệch áp nhẹ giữa các cell, nên sạc đầy để BMS cân bằng.'),
  poor('Lệch áp cao', 'Các cell lệch áp đáng kể (>80mV), cần cắm sạc qua đêm.'),
  critical('BÁO ĐỘNG', 'Nguy cơ tụt áp cell nghiêm trọng (>120mV), hạn chế vặn ga mạnh!');

  final String label;
  final String description;
  const CellBalanceGrade(this.label, this.description);
}

enum ThermalStatus {
  cool('Mát', 0xFF10B981),
  normal('Bình thường', 0xFF0EA5E9),
  warm('Ấm', 0xFFF59E0B),
  hot('Nóng', 0xFFF97316),
  critical('Nguy hiểm', 0xFFEF4444);

  final String label;
  final int colorValue;
  const ThermalStatus(this.label, this.colorValue);
}

class ThermalZone {
  final String name;
  final double temperature;
  final double warningTemp;
  final double criticalTemp;
  final ThermalStatus status;

  const ThermalZone({
    required this.name,
    required this.temperature,
    required this.warningTemp,
    required this.criticalTemp,
    required this.status,
  });

  factory ThermalZone.evaluate({
    required String name,
    required double temp,
    required double warningTemp,
    required double criticalTemp,
  }) {
    final ThermalStatus status;
    if (temp <= 0) {
      status = ThermalStatus.cool;
    } else if (temp <= 35) {
      status = ThermalStatus.cool;
    } else if (temp < warningTemp - 10) {
      status = ThermalStatus.normal;
    } else if (temp < warningTemp) {
      status = ThermalStatus.warm;
    } else if (temp < criticalTemp) {
      status = ThermalStatus.hot;
    } else {
      status = ThermalStatus.critical;
    }

    return ThermalZone(
      name: name,
      temperature: temp,
      warningTemp: warningTemp,
      criticalTemp: criticalTemp,
      status: status,
    );
  }
}

class ObdDiagnosticItem {
  final int id;
  final String name;
  final String code;
  final bool isHealthy;
  final String severity; // 'Tốt', 'Cảnh báo', 'Khẩn cấp'
  final String description;
  final String recommendation;

  const ObdDiagnosticItem({
    required this.id,
    required this.name,
    required this.code,
    required this.isHealthy,
    required this.severity,
    required this.description,
    required this.recommendation,
  });
}

class BatteryHealthReport {
  final List<double> cellVoltages;
  final int cellCount;
  final double maxCellVoltage;
  final int maxCellIndex;
  final double minCellVoltage;
  final int minCellIndex;
  final double avgCellVoltage;
  final double deltaVoltageMv;
  final CellBalanceGrade balanceGrade;
  final int healthPercentage; // SOH 0-100%
  final double packVoltage;
  final double currentAmp;
  final bool isBalancing;
  final int chargeCycles;
  final double internalResistanceMo; // mOhm
  final ThermalZone motorThermal;
  final ThermalZone ecuThermal;
  final ThermalZone bmsThermal;
  final List<ObdDiagnosticItem> obdItems;
  final int safetyScore; // 0-100
  final bool hasLiveTelemetry;
  final bool isSimulated;
  final String packConfigName;
  final int rawErrorCode;

  const BatteryHealthReport({
    required this.cellVoltages,
    required this.cellCount,
    required this.maxCellVoltage,
    required this.maxCellIndex,
    required this.minCellVoltage,
    required this.minCellIndex,
    required this.avgCellVoltage,
    required this.deltaVoltageMv,
    required this.balanceGrade,
    required this.healthPercentage,
    required this.packVoltage,
    required this.currentAmp,
    required this.isBalancing,
    required this.chargeCycles,
    required this.internalResistanceMo,
    required this.motorThermal,
    required this.ecuThermal,
    required this.bmsThermal,
    required this.obdItems,
    required this.safetyScore,
    this.hasLiveTelemetry = false,
    this.isSimulated = false,
    this.packConfigName = 'Đang chờ BMS...',
    this.rawErrorCode = 0,
  });
}

class BatteryDiagnosticsService {
  BatteryDiagnosticsService._();

  static BatteryHealthReport analyze({
    BikeLogMsg? telemetry,
    BatteryLogMsg? battery,
    String? modelName,
  }) {
    final bool hasLiveTelemetry = (telemetry != null && telemetry.voltage > 0) || battery != null;
    final packVoltage = battery?.voltage ?? telemetry?.voltage ?? 0.0;
    final currentAmp = battery?.current ?? telemetry?.phase ?? 0.0;

    List<double> cells = [];
    bool isSimulated = false;
    final String packConfig;

    if (battery != null && battery.cellVols.isNotEmpty) {
      // 1. DỮ LIỆU THỰC TẾ TỪ BLUETOOTH BMS (Single Source of Truth)
      // Hiển thị chính xác số cell thực tế nhận được từ BMS xe.
      cells = List<double>.from(battery.cellVols);
      isSimulated = false;
      packConfig = '${cells.length}S (${cells.length} Cell)';
    } else {
      // 2. Khi offline hoặc xe chưa truyền bản tin BMS:
      // Không bịa số cell, không dùng hàm sin/cos tạo sóng giả.
      cells = const [];
      isSimulated = true;
      packConfig = 'Đang chờ BMS...';
    }

    final double vMax;
    final int maxIdx;
    final double vMin;
    final int minIdx;
    final double avgV;
    final double deltaMv;
    final CellBalanceGrade grade;

    if (cells.isNotEmpty) {
      double maxVal = cells.first;
      int mIdx = 1;
      double minVal = cells.first;
      int nIdx = 1;
      double sum = 0.0;

      for (int i = 0; i < cells.length; i++) {
        final v = cells[i];
        sum += v;
        if (v > maxVal) {
          maxVal = v;
          mIdx = i + 1;
        }
        if (v < minVal) {
          minVal = v;
          nIdx = i + 1;
        }
      }
      vMax = maxVal;
      maxIdx = mIdx;
      vMin = minVal;
      minIdx = nIdx;
      avgV = sum / cells.length;
      deltaMv = (vMax - vMin) * 1000.0;

      if (deltaMv <= 20.0) {
        grade = CellBalanceGrade.excellent;
      } else if (deltaMv <= 45.0) {
        grade = CellBalanceGrade.good;
      } else if (deltaMv <= 80.0) {
        grade = CellBalanceGrade.fair;
      } else if (deltaMv <= 120.0) {
        grade = CellBalanceGrade.poor;
      } else {
        grade = CellBalanceGrade.critical;
      }
    } else {
      vMax = 0.0;
      maxIdx = 0;
      vMin = 0.0;
      minIdx = 0;
      avgV = 0.0;
      deltaMv = 0.0;
      grade = CellBalanceGrade.unknown;
    }

    // Ước lượng SOH (State of Health)
    final cycles = battery?.socCycles.round() ?? (telemetry != null ? (telemetry.odo / 150.0).round() : 0);
    int health = hasLiveTelemetry ? (100 - (cycles * 0.03).round()) : 100;
    if (hasLiveTelemetry) {
      if (deltaMv > 80) health -= 5;
      if (deltaMv > 120) health -= 10;
      health = health.clamp(60, 100);
    }

    // Bản đồ nhiệt 3 điểm: Khi offline trả về 0.0, không bịa nhiệt độ
    final motorZone = ThermalZone.evaluate(
      name: 'Động cơ (Motor)',
      temp: telemetry?.motor ?? (hasLiveTelemetry ? 32.0 : 0.0),
      warningTemp: 75.0,
      criticalTemp: 90.0,
    );

    final ecuZone = ThermalZone.evaluate(
      name: 'Biến tần (ECU)',
      temp: telemetry?.ecu ?? (hasLiveTelemetry ? 30.0 : 0.0),
      warningTemp: 65.0,
      criticalTemp: 80.0,
    );

    final bmsZone = ThermalZone.evaluate(
      name: 'Khối Pin (BMS)',
      temp: telemetry?.bmsTemp ?? (battery?.ntcs.isNotEmpty == true ? battery!.ntcs.first : (hasLiveTelemetry ? 29.0 : 0.0)),
      warningTemp: 48.0,
      criticalTemp: 58.0,
    );

    // Quét & Giải mã mã lỗi hệ thống OBD theo chuẩn VESC Fault Code
    final errorCode = telemetry?.error ?? 0;
    final obdItems = _evaluateObdSystems(errorCode, telemetry, battery, packVoltage, hasLiveTelemetry);

    // Điểm an toàn vận hành
    final activeErrors = obdItems.where((item) => !item.isHealthy).length;
    final safetyScore = hasLiveTelemetry ? max(0, 100 - (activeErrors * 25)) : 0;

    return BatteryHealthReport(
      cellVoltages: cells,
      cellCount: cells.length,
      maxCellVoltage: vMax,
      maxCellIndex: maxIdx,
      minCellVoltage: vMin,
      minCellIndex: minIdx,
      avgCellVoltage: avgV,
      deltaVoltageMv: deltaMv,
      balanceGrade: grade,
      healthPercentage: health,
      packVoltage: packVoltage,
      currentAmp: currentAmp,
      isBalancing: (battery?.balancing ?? 0) != 0,
      chargeCycles: cycles,
      internalResistanceMo: battery?.resistor ?? (hasLiveTelemetry ? 18.5 : 0.0),
      motorThermal: motorZone,
      ecuThermal: ecuZone,
      bmsThermal: bmsZone,
      obdItems: obdItems,
      safetyScore: safetyScore,
      hasLiveTelemetry: hasLiveTelemetry,
      isSimulated: isSimulated,
      packConfigName: packConfig,
      rawErrorCode: errorCode,
    );
  }

  /// Giải mã mã lỗi phần cứng: Phối hợp chuẩn VESC mc_fault_code Enum và Telemetry xe thực tế
  static List<ObdDiagnosticItem> _evaluateObdSystems(
    int errorCode,
    BikeLogMsg? telemetry,
    BatteryLogMsg? battery,
    double packVoltage,
    bool hasLiveTelemetry,
  ) {
    if (!hasLiveTelemetry) {
      return const [
        ObdDiagnosticItem(
          id: 1,
          name: 'IC Lái Cổng Công Suất (DRV)',
          code: 'VESC-FAULT-03',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để chẩn đoán mạch lái MOSFET.',
        ),
        ObdDiagnosticItem(
          id: 2,
          name: 'Bảo Vệ Quá Dòng (Over-Current)',
          code: 'VESC-FAULT-04',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để chẩn đoán dòng tải biến tần.',
        ),
        ObdDiagnosticItem(
          id: 3,
          name: 'Nhiệt Độ Biến Tần ECU',
          code: 'VESC-TEMP-FET',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để giám sát nhiệt độ ECU.',
        ),
        ObdDiagnosticItem(
          id: 4,
          name: 'Nhiệt Độ Động Cơ (Motor)',
          code: 'VESC-TEMP-MOT',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để giám sát nhiệt độ motor.',
        ),
        ObdDiagnosticItem(
          id: 5,
          name: 'Điện Áp Thấp / Cạn Bình (Under-Voltage)',
          code: 'VESC-FAULT-02',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để đo điện áp pack pin.',
        ),
        ObdDiagnosticItem(
          id: 6,
          name: 'Điện Áp Cao Bất Thường (Over-Voltage)',
          code: 'VESC-FAULT-01',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để kiểm tra điện áp bus sạc/recup.',
        ),
        ObdDiagnosticItem(
          id: 7,
          name: 'Cảm Biến Vị Trí Góc Quay / Encoder',
          code: 'VESC-FAULT-ENC',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để kiểm tra tín hiệu encoder rotor.',
        ),
        ObdDiagnosticItem(
          id: 8,
          name: 'Cảm Biến Nhiệt Pack Pin (BMS NTC)',
          code: 'BMS-TEMP-NTC',
          isHealthy: true,
          severity: 'Chờ kết nối',
          description: 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.',
          recommendation: 'Kết nối Bluetooth với xe để giám sát cảm biến nhiệt cell pin.',
        ),
      ];
    }
    // VESC mc_fault_code enumeration:
    // 0: FAULT_CODE_NONE
    // 1: FAULT_CODE_OVER_VOLTAGE
    // 2: FAULT_CODE_UNDER_VOLTAGE
    // 3: FAULT_CODE_DRV
    // 4: FAULT_CODE_ABS_OVER_CURRENT
    // 5: FAULT_CODE_OVER_TEMP_FET
    // 6: FAULT_CODE_OVER_TEMP_MOTOR
    // 7: FAULT_CODE_GATE_DRIVER_OVER_VOLTAGE
    // 8: FAULT_CODE_GATE_DRIVER_UNDER_VOLTAGE
    // 9: FAULT_CODE_MCU_UNDER_VOLTAGE
    // 10: FAULT_CODE_BOOTING_FROM_WATCHDOG_RESET
    // 11: FAULT_CODE_ENCODER_SPI
    // 12: FAULT_CODE_ENCODER_SINCOS_BELOW_MIN_AMPLITUDE
    // 13: FAULT_CODE_ENCODER_SINCOS_ABOVE_MAX_AMPLITUDE
    // 14: FAULT_CODE_FLASH_CORRUPTION
    // 15: FAULT_CODE_HIGH_OFFSET_CURRENT_SENSOR_1
    // 16: FAULT_CODE_HIGH_OFFSET_CURRENT_SENSOR_2
    // 17: FAULT_CODE_HIGH_OFFSET_CURRENT_SENSOR_3
    // 18: FAULT_CODE_UNBALANCED_CURRENTS
    // 19: FAULT_CODE_BRK
    // 20: FAULT_CODE_RESOLVER_LOT
    // 21: FAULT_CODE_RESOLVER_DOS
    // 22: FAULT_CODE_RESOLVER_LOS

    final bool isDrvFault = errorCode == 3;
    final bool isOverCurrent = errorCode == 4 || errorCode == 18;
    final bool isEcuOverTemp = errorCode == 5 || (telemetry != null && telemetry.ecu > 75.0);
    final bool isMotorOverTemp = errorCode == 6 || (telemetry != null && telemetry.motor > 85.0);
    final bool isOverVoltage = errorCode == 1;
    final bool isUnderVoltage = errorCode == 2 || (packVoltage > 0.0 && packVoltage < 65.0);
    final bool isBmsOverTemp = battery != null && battery.ntcs.any((t) => t > 55.0);
    final bool isSensorFault = errorCode == 11 || errorCode == 12 || errorCode == 13 || errorCode == 20 || errorCode == 21 || errorCode == 22;

    return [
      ObdDiagnosticItem(
        id: 1,
        name: 'IC Lái Cổng Công Suất (DRV)',
        code: 'VESC-FAULT-03',
        isHealthy: !isDrvFault,
        severity: isDrvFault ? 'Khẩn cấp' : 'Tốt',
        description: isDrvFault
            ? 'Phát hiện lỗi phần cứng IC lái cổng MOSFET (DRV830x). Biến tần đã tự ngắt để tránh nổ transistor.'
            : 'Mạch lái xung MOSFET hoạt động chính xác, điện áp kích cổng ổn định.',
        recommendation: isDrvFault
            ? 'Tắt nguồn xe ngay lập tức. Đưa xe về Dat Bike Store hoặc trạm dịch vụ để kiểm tra bo mạch ECU.'
            : 'Mạch công suất hoạt động hoàn hảo.',
      ),
      ObdDiagnosticItem(
        id: 2,
        name: 'Bảo Vệ Quá Dòng (Over-Current)',
        code: 'VESC-FAULT-04',
        isHealthy: !isOverCurrent,
        severity: isOverCurrent ? 'Khẩn cấp' : 'Tốt',
        description: isOverCurrent
            ? 'Dòng xả tức thời vượt ngưỡng giới hạn tuyệt đối của biến tần VESC (>350A).'
            : 'Dòng tải nằm trong giới hạn thiết kế an toàn của bo công suất MOSFET.',
        recommendation: isOverCurrent
            ? 'Dừng xe, đợi 2 phút. Tránh kéo ga thốc đột ngột khi xe đang chở quá tải hoặc leo dốc gắt.'
            : 'Bộ điều tốc hoạt động đúng định mức tải.',
      ),
      ObdDiagnosticItem(
        id: 3,
        name: 'Nhiệt Độ Biến Tần ECU',
        code: 'VESC-TEMP-FET',
        isHealthy: !isEcuOverTemp,
        severity: isEcuOverTemp ? 'Cảnh báo' : 'Tốt',
        description: isEcuOverTemp
            ? 'Nhiệt độ bo điều khiển ECU vượt ngưỡng an toàn (${telemetry?.ecu.toStringAsFixed(1) ?? "80"}°C), công suất đã bị giới hạn để làm mát.'
            : 'Nhiệt độ bo ECU mát mẻ (${telemetry?.ecu.toStringAsFixed(1) ?? "30"}°C), keo tản nhiệt và quạt làm mát hiệu quả.',
        recommendation: isEcuOverTemp
            ? 'Giảm tốc độ, tránh ép ga liên tục. Cho xe nghỉ ở nơi thoáng mát 10-15 phút.'
            : 'Tản nhiệt ECU tối ưu.',
      ),
      ObdDiagnosticItem(
        id: 4,
        name: 'Nhiệt Độ Động Cơ (Motor)',
        code: 'VESC-TEMP-MOT',
        isHealthy: !isMotorOverTemp,
        severity: isMotorOverTemp ? 'Cảnh báo' : 'Tốt',
        description: isMotorOverTemp
            ? 'Cảm biến nhiệt phát hiện cuộn dây động cơ bánh sau quá nóng (${telemetry?.motor.toStringAsFixed(1) ?? "85"}°C).'
            : 'Nhiệt độ động cơ trong ngưỡng lý tưởng (${telemetry?.motor.toStringAsFixed(1) ?? "32"}°C).',
        recommendation: isMotorOverTemp
            ? 'Dừng xe nghỉ để động cơ giảm nhiệt độ trước khi tiếp tục hành trình dài.'
            : 'Hệ thống truyền động motor hoạt động bền bỉ.',
      ),
      ObdDiagnosticItem(
        id: 5,
        name: 'Điện Áp Thấp / Cạn Bình (Under-Voltage)',
        code: 'VESC-FAULT-02',
        isHealthy: !isUnderVoltage,
        severity: isUnderVoltage ? 'Cảnh báo' : 'Tốt',
        description: isUnderVoltage
            ? 'Điện áp pack pin tụt dưới ngưỡng cắt bảo vệ (${packVoltage.toStringAsFixed(1)}V), xe chuyển sang chế độ bảo tồn (Rùa).'
            : 'Điện áp ổn định (${packVoltage.toStringAsFixed(1)}V), không có hiện tượng sụt áp sâu.',
        recommendation: isUnderVoltage
            ? 'Cần cắm sạc ngay. Tránh để xe kiệt pin dưới 0% trong thời gian dài.'
            : 'Nguồn điện cung cấp dồi dào.',
      ),
      ObdDiagnosticItem(
        id: 6,
        name: 'Điện Áp Cao Bất Thường (Over-Voltage)',
        code: 'VESC-FAULT-01',
        isHealthy: !isOverVoltage,
        severity: isOverVoltage ? 'Khẩn cấp' : 'Tốt',
        description: isOverVoltage
            ? 'Điện áp ngõ vào vượt quá giới hạn cực đại (>98V), thường do phanh tái sinh RECUP khi pin đang đầy 100%.'
            : 'Điện áp bus nằm trong ngưỡng an toàn tuyệt đối.',
        recommendation: isOverVoltage
            ? 'Hạn chế sử dụng phanh tái sinh liên tục khi pin vừa sạc đầy 100% khi đổ dốc.'
            : 'Hệ thống điều hòa điện áp bus hoạt động tin cậy.',
      ),
      ObdDiagnosticItem(
        id: 7,
        name: 'Cảm Biến Vị Trí Góc Quay / Encoder',
        code: 'VESC-FAULT-ENC',
        isHealthy: !isSensorFault,
        severity: isSensorFault ? 'Khẩn cấp' : 'Tốt',
        description: isSensorFault
            ? 'ECU mất tín hiệu hoặc biên độ sin/cos góc quay từ cảm biến động cơ không chuẩn.'
            : 'Tín hiệu góc quay FOC đồng bộ chính xác, không phát hiện mất bước.',
        recommendation: isSensorFault
            ? 'Kiểm tra giắc cắm encoder động cơ bánh sau và bó dây tín hiệu.'
            : 'Hệ thống định vị góc quay rotor chính xác.',
      ),
      ObdDiagnosticItem(
        id: 8,
        name: 'Cảm Biến Nhiệt Pack Pin (BMS NTC)',
        code: 'BMS-TEMP-NTC',
        isHealthy: !isBmsOverTemp,
        severity: isBmsOverTemp ? 'Khẩn cấp' : 'Tốt',
        description: isBmsOverTemp
            ? 'Cảm biến NTC phát hiện nhiệt độ pack pin vượt ngưỡng nguy hại (>55°C).'
            : 'Nhiệt độ khối cell pin đồng đều và nằm trong vùng tối ưu hóa tuổi thọ.',
        recommendation: isBmsOverTemp
            ? 'CẢNH BÁO: Tắt nguồn ngay! Không cắm sạc khi pin đang quá nhiệt.'
            : 'Điều kiện môi trường cell pin lý tưởng.',
      ),
    ];
  }
}
