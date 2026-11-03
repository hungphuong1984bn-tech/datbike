// Tab CONTROL — Regen và Smart Key (và các điều khiển xe) trong một nơi.
// Chỉ điều hướng + hiển thị trạng thái thật. KHÔNG gửi lệnh ở đây:
// mọi thao tác ghi vẫn đi qua các màn hình/controller đã có cổng an toàn.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/proximity/proximity_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../control_center/control_center_screen.dart';
import '../proximity/proximity_screen.dart';
import '../regen/regen_screen.dart';
import '../settings/vehicle_settings_screen.dart';
import 'hub_widgets.dart';

class ControlHubScreen extends ConsumerWidget {
  const ControlHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(bleProvider.select((s) => s.phase == BlePhase.connected));
    final locked = ref.watch(bleProvider.select((s) => s.isLocked));
    final prox = ref.watch(proximityProvider);
    final dist = prox.distanceM;

    return DsScaffold(
      title: 'Điều khiển',
      subtitle: 'Regen · Smart Key · Chế độ lái',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.huge),
        children: [
          const LiveStateBanner(),
          const SizedBox(height: AppSpacing.sm),
          HubGrid(children: [
            HubStat(
              icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              label: 'Khóa an toàn',
              value: connected ? (locked ? 'Đang khóa' : 'Đã mở') : null,
              accent: locked ? AppColors.amber : AppColors.tertiary,
            ),
            HubStat(
              icon: Icons.social_distance_rounded,
              label: 'Khoảng cách điện thoại',
              value: (connected && dist != null) ? dist.toStringAsFixed(1) : null,
              unit: 'm',
            ),
          ]),
          const DsSectionHeader('Smart Key & Regen'),
          HubLink(
              icon: Icons.sensors_rounded,
              title: 'Smart Key',
              subtitle: prox.message,
              builder: () => const ProximityScreen()),
          HubLink(
              icon: Icons.energy_savings_leaf_rounded,
              title: 'Regen 5 cấp độ',
              subtitle: 'Giám sát dòng nạp ngược và mức thu hồi (chỉ đọc)',
              builder: () => const RegenScreen(),
              color: AppColors.tertiary),
          const DsSectionHeader('Chế độ lái & xe'),
          HubLink(
              icon: Icons.tune_rounded,
              title: 'Trung tâm điều khiển',
              subtitle: 'Chế độ lái, phản hồi ga, giới hạn tốc độ',
              builder: () => const ControlCenterScreen()),
          HubLink(
              icon: Icons.settings_input_component_rounded,
              title: 'Cài đặt xe và phanh',
              subtitle: 'Thiết lập xe, phanh, khoảng cách nhận diện',
              builder: () => const VehicleSettingsScreen(),
              color: AppColors.textPrimary),
        ],
      ),
    );
  }
}
