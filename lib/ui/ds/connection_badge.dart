// ConnectionBadge — trạng thái kết nối BLE chuẩn, dùng ở mọi màn hình.
// Chỉ ĐỌC enum BlePhase; không động vào luồng kết nối.

import 'package:flutter/material.dart';

import '../../core/ble/ble_controller.dart' show BlePhase;
import '../app_theme.dart';
import '../widgets.dart';

class ConnectionBadge extends StatelessWidget {
  final BlePhase phase;
  const ConnectionBadge({super.key, required this.phase});

  static String labelOf(BlePhase p) {
    switch (p) {
      case BlePhase.connected:
        return 'Đã kết nối';
      case BlePhase.connecting:
        return 'Đang kết nối';
      case BlePhase.reconnecting:
        return 'Đang kết nối lại';
      case BlePhase.scanning:
        return 'Đang tìm xe';
      case BlePhase.disconnected:
        return 'Mất kết nối';
      case BlePhase.idle:
        return 'Chưa kết nối';
    }
  }

  static Color colorOf(BlePhase p) {
    switch (p) {
      case BlePhase.connected:
        return AppColors.tertiary;
      case BlePhase.connecting:
      case BlePhase.reconnecting:
      case BlePhase.scanning:
        return AppColors.amber;
      case BlePhase.disconnected:
        return AppColors.red;
      case BlePhase.idle:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = phase == BlePhase.connecting ||
        phase == BlePhase.reconnecting ||
        phase == BlePhase.scanning;
    return AnimatedSwitcher(
      duration: AppMotion.normal,
      child: StatusPill(
        key: ValueKey(phase),
        label: labelOf(phase),
        color: colorOf(phase),
        pulse: busy || phase == BlePhase.connected,
      ),
    );
  }
}
