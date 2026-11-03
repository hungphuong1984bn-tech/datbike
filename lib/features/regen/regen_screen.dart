// Màn hình Regen (phanh tái sinh). Bảng 5 cấp nằm ở regen_level_panel.dart —
// hiện KHÓA vì chưa có characteristic Regen độc lập nào được xác minh. Grab được điều khiển riêng ở Trung tâm điều khiển
// vận hành (không coi Grab = Regen).
//
// Giao diện: khung DsScaffold thống nhất; dải LiveStateBanner báo thẳng khi chưa/mất
// kết nối hoặc dữ liệu đã cũ (không chỉ dựa vào thẻ bên dưới).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../control_center/regen_monitor_card.dart';
import 'regen_level_panel.dart';

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
          const RegenLevelPanel(),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            key: const Key('regen_open_evidence'),
            onPressed: () => Navigator.of(context).pushNamed('/regen-evidence'),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Mở Bằng chứng Regen'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.minTap),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
