// Màn hình Regen (phanh tái sinh) — CHỈ ĐỌC.
// Chưa có characteristic Regen độc lập nào được xác minh, nên màn hình này
// không có điều khiển nào. Grab được điều khiển riêng ở Trung tâm điều khiển
// vận hành (không coi Grab = Regen).

import 'package:flutter/material.dart';

import '../control_center/regen_monitor_card.dart';

class RegenScreen extends StatelessWidget {
  const RegenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phanh tái sinh (Regen)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const RegenMonitorCard(),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('regen_open_control_center'),
              onPressed: () => Navigator.of(context).pushNamed('/control-center'),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Mở Trung tâm điều khiển vận hành'),
            ),
          ],
        ),
      ),
    );
  }
}
