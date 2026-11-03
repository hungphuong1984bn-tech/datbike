// Tab VEHICLE — thông số xe + lối vào Pin / Chẩn đoán / Vận hành.
// Mọi số liệu lấy từ telemetry thật (bleProvider); thiếu dữ liệu → "N/A".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../battery/battery_diagnostics_screen.dart';
import '../ble_diagnostics/ble_diagnostics_screen.dart';
import '../charging/charging_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../operations/operations_screen.dart';
import 'hub_widgets.dart';
import 'trip_stats_card.dart';

class VehicleHubScreen extends ConsumerWidget {
  const VehicleHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(bleProvider.select((s) => s.lastTelemetry));
    final b = ref.watch(bleProvider.select((s) => s.lastBattery));
    final connected =
        ref.watch(bleProvider.select((s) => s.phase == BlePhase.connected));
    // Đã kết nối nhưng chưa có gói đầu tiên → khung chờ (không hiện "N/A" gây hiểu nhầm).
    final waiting = connected && t == null && b == null;

    String? f(double? v, int d) => v == null ? null : v.toStringAsFixed(d);

    return DsScaffold(
      title: 'Thông số xe',
      subtitle: 'Datbike Quantum S1',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.huge),
        children: [
          const LiveStateBanner(),
          const SizedBox(height: AppSpacing.sm),
          if (waiting)
            const SkeletonGrid()
          else
          HubGrid(children: [
            HubStat(
                icon: Icons.speed_rounded,
                label: 'Tốc độ',
                value: t != null ? f(t.speed, 0) : null,
                unit: 'km/h'),
            HubStat(
                icon: Icons.battery_std_rounded,
                label: 'Pin (SOC)',
                value: t != null ? '${t.percent}' : null,
                unit: '%',
                accent: AppColors.tertiary),
            HubStat(
                icon: Icons.route_rounded,
                label: 'Quãng đường còn lại',
                value: t != null ? f(t.kmLeft, 0) : null,
                unit: 'km'),
            HubStat(
                icon: Icons.pin_drop_outlined,
                label: 'ODO',
                value: t != null ? f(t.odo, 0) : null,
                unit: 'km'),
            HubStat(
                icon: Icons.bolt_rounded,
                label: 'Điện áp pin',
                value: b != null ? f(b.voltage, 1) : (t != null ? f(t.voltage, 1) : null),
                unit: 'V'),
            HubStat(
                icon: Icons.electric_meter_rounded,
                label: 'Dòng điện pin',
                value: b != null ? f(b.current, 1) : null,
                unit: 'A'),
            HubStat(
                icon: Icons.thermostat_rounded,
                label: 'Nhiệt độ động cơ',
                value: t != null ? f(t.motor, 0) : null,
                unit: '°C'),
            HubStat(
                icon: Icons.memory_rounded,
                label: 'Nhiệt độ bộ điều khiển',
                value: t != null ? f(t.ecu, 0) : null,
                unit: '°C'),
          ]),
          const DsSectionHeader('Thống kê hành trình',
              hint: 'Theo ngày, tuần, tháng — từ các chuyến đã ghi'),
          const TripStatsCard(),
          const DsSectionHeader('Trung tâm',
              hint: 'Mở màn hình chi tiết của từng phân hệ'),
          HubLink(
              icon: Icons.battery_charging_full_rounded,
              title: 'Bác sĩ Pin',
              subtitle: 'Sức khỏe, cell, BMS, cân bằng, bảo vệ',
              builder: () => const BatteryDiagnosticsScreen(),
              color: AppColors.tertiary),
          HubLink(
              icon: Icons.ev_station_rounded,
              title: 'Năng lượng & Sạc',
              subtitle: 'Phiên sạc, công suất, thời gian dự kiến',
              builder: () => const ChargingScreen()),
          HubLink(
              icon: Icons.insights_rounded,
              title: 'Vận hành & Hành trình',
              subtitle: 'Thống kê chuyến đi và lịch sử vận hành',
              builder: () => const OperationsScreen()),
          HubLink(
              icon: Icons.health_and_safety_rounded,
              title: 'Chẩn đoán xe',
              subtitle: 'Mã lỗi, trạng thái bộ điều khiển',
              builder: () => const DiagnosticsScreen(),
              color: AppColors.amber),
          HubLink(
              icon: Icons.bluetooth_searching_rounded,
              title: 'Bluetooth & Nhật ký kết nối',
              subtitle: 'Chất lượng BLE, log chẩn đoán, kết nối lại',
              builder: () => const BleDiagnosticsScreen()),
        ],
      ),
    );
  }
}
