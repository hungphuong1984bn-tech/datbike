import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/proto/bike_log.dart';
import 'package:mybike_app/core/services/battery_diagnostics_service.dart';
import 'package:mybike_app/core/services/charging_router_service.dart';

void main() {
  group('BatteryDiagnosticsService Tests', () {
    test('Offline / No BMS telemetry returns empty cells and unknown balance grade', () {
      final report = BatteryDiagnosticsService.analyze(
        telemetry: BikeLogMsg()..voltage = 84.0..phase = 0.0,
        battery: null,
      );

      // Tuyệt đối không sinh mảng cell giả mạo
      expect(report.cellVoltages, isEmpty);
      expect(report.cellCount, 0);
      expect(report.isSimulated, isTrue);
      expect(report.balanceGrade, CellBalanceGrade.unknown);
      expect(report.deltaVoltageMv, 0.0);
      expect(report.packConfigName, 'Đang chờ BMS...');
    });

    test('Offline without telemetry or battery reports hasLiveTelemetry false and OBD waiting', () {
      final report = BatteryDiagnosticsService.analyze(
        telemetry: null,
        battery: null,
      );

      expect(report.hasLiveTelemetry, isFalse);
      expect(report.safetyScore, 0);
      expect(report.motorThermal.temperature, 0.0);
      expect(report.ecuThermal.temperature, 0.0);
      expect(report.bmsThermal.temperature, 0.0);
      expect(report.internalResistanceMo, 0.0);
      expect(report.obdItems.length, 8);
      expect(report.obdItems.every((item) => item.severity == 'Chờ kết nối'), isTrue);
    });

    test('Real BMS telemetry with 23 cells returns exact cell count and real balance', () {
      final realVoltages = List.generate(23, (i) => 3.650 + (i * 0.001));
      final bms = BatteryLogMsg()
        ..voltage = 84.1
        ..current = -5.0
        ..cellVols = realVoltages;

      final report = BatteryDiagnosticsService.analyze(battery: bms);

      expect(report.cellVoltages.length, 23);
      expect(report.cellCount, 23);
      expect(report.isSimulated, isFalse);
      expect(report.packConfigName, '23S (23 Cell)');
      expect(report.maxCellVoltage, closeTo(3.672, 0.001));
      expect(report.minCellVoltage, closeTo(3.650, 0.001));
      expect(report.balanceGrade, CellBalanceGrade.good);
    });

    test('VESC mc_fault_code 3 (DRV) is decoded precisely without bitmask corruption', () {
      final telemetry = BikeLogMsg()
        ..voltage = 84.0
        ..error = 3; // VESC DRV Fault

      final report = BatteryDiagnosticsService.analyze(telemetry: telemetry);

      expect(report.rawErrorCode, 3);
      final drvItem = report.obdItems.firstWhere((item) => item.code == 'VESC-FAULT-03');
      expect(drvItem.isHealthy, isFalse);
      expect(drvItem.severity, 'Khẩn cấp');

      // Các lỗi khác không bị ảnh hưởng sai lệch do bitmask
      final overCurrent = report.obdItems.firstWhere((item) => item.code == 'VESC-FAULT-04');
      expect(overCurrent.isHealthy, isTrue);
    });
  });

  group('ChargingRouterService Tests', () {
    test('Charging detected from positive phase current without mock 220V/36C', () {
      // Quy ước dấu verify session 20261022T212957: DƯƠNG = dòng sạc vào pin,
      // ÂM = xe xả pin (chạy xe -8..-25A kèm điện áp xả 76.8→76.4V).
      final telemetry = BikeLogMsg()
        ..voltage = 84.0
        ..phase = 15.0; // Dòng nạp 15A

      final report = ChargingRouterService.analyzeCharging(telemetry: telemetry);

      expect(report.isCharging, isTrue);
      expect(report.powerWatts, 84 * 15);
      // Không được trả về 220V hay 36°C mock khi không có bản tin bộ sạc
      expect(report.gridVoltageRms, isNull);
      expect(report.fetTemp, isNull);
      expect(report.isGridUnstable, isFalse);
      expect(report.isFetOverheat, isFalse);
    });

    test('Not charging when phase is non-positive and charger is null', () {
      final telemetry = BikeLogMsg()
        ..voltage = 76.4
        ..phase = -10.0; // Xe đang xả dòng kéo tải

      final report = ChargingRouterService.analyzeCharging(telemetry: telemetry);

      expect(report.isCharging, isFalse);
      expect(report.powerWatts, 0);
      expect(report.gridVoltageRms, isNull);
      expect(report.fetTemp, isNull);
    });
  });
}
