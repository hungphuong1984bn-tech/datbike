// Màn hình Regen (phanh tái sinh) — CHỈ ĐỌC.
// Chưa có characteristic Regen độc lập nào được xác minh, nên màn hình này
// không có điều khiển nào. Grab được điều khiển riêng ở Trung tâm điều khiển
// vận hành (không coi Grab = Regen).
//
// Giao diện: khung DsScaffold thống nhất; dải LiveStateBanner báo thẳng khi chưa/mất
// kết nối hoặc dữ liệu đã cũ (không chỉ dựa vào thẻ bên dưới).

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../control_center/regen_monitor_card.dart';

class RegenScreen extends StatelessWidget {
  const RegenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DsScaffold(
      title: 'Phanh tái sinh (Regen)',
      subtitle: 'Chỉ đọc · chưa có điều khiển',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH,
          AppSpacing.sm,
          AppSpacing.pageH,
          AppSpacing.huge,
        ),
        children: [
          const LiveStateBanner(margin: EdgeInsets.only(bottom: AppSpacing.md)),
          const RegenMonitorCard(),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            key: const Key('regen_open_control_center'),
            onPressed: () => Navigator.of(context).pushNamed('/control-center'),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Mở Trung tâm điều khiển vận hành'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.minTap),
            ),
          ),
        ],
      ),
    );
  }
}
