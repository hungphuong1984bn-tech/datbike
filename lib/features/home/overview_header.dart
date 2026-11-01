// Header gọn của tab Tổng quan: logo · tên xe (chạm để đổi xe) · trạng thái
// Bluetooth · lối tắt HUD. Cao ~56dp để nhường chỗ cho thông tin quan trọng.
//
// Chỉ nhận tham số thuần: không đọc BLE, không gửi lệnh.

import 'package:flutter/material.dart';

import '../../core/ble/ble_controller.dart' show BlePhase;
import '../../ui/app_theme.dart';
import '../../ui/brand_logo.dart';
import '../../ui/ds/ds.dart';

class OverviewHeader extends StatelessWidget {
  final BlePhase phase;

  /// Tên xe do xe/hồ sơ cung cấp; null → "Xe điện".
  final String? bikeName;

  final VoidCallback onSwitchBike;
  final VoidCallback onConnect;
  final VoidCallback onHud;

  const OverviewHeader({
    super.key,
    required this.phase,
    required this.bikeName,
    required this.onSwitchBike,
    required this.onConnect,
    required this.onHud,
  });

  @override
  Widget build(BuildContext context) {
    final connected = phase == BlePhase.connected;
    // Màn hẹp (≤ 340dp): chỉ hiện biểu tượng Bluetooth để tên xe còn chỗ.
    final compact = MediaQuery.sizeOf(context).width < 340;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const ThBikeLogo(size: 38, glow: false),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Xe đang chọn: ${bikeName ?? 'Xe điện'}. Chạm để đổi xe',
              excludeSemantics: true,
              child: InkWell(
                onTap: onSwitchBike,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSizes.minTap),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THBIKE',
                        style: AppTypography.labelSm(color: AppColors.primary)
                            .copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              bikeName ?? 'Xe điện',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.evWide(fontSize: 17, letterSpacing: -0.2),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.unfold_more_rounded, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Semantics(
            button: !connected,
            label: connected
                ? 'Bluetooth: ${ConnectionBadge.labelOf(phase)}'
                : 'Bluetooth: ${ConnectionBadge.labelOf(phase)}. Chạm để kết nối',
            excludeSemantics: true,
            child: InkWell(
              onTap: connected ? null : onConnect,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: compact
                  ? _CompactBluetooth(phase: phase)
                  : ConnectionBadge(phase: phase),
            ),
          ),
          IconButton(
            tooltip: 'Đồng hồ lái (HUD)',
            constraints: const BoxConstraints(
                minWidth: AppSizes.minTap, minHeight: AppSizes.minTap),
            icon: Icon(Icons.speed_rounded, size: 22, color: AppColors.textPrimary),
            onPressed: onHud,
          ),
        ],
      ),
    );
  }
}

/// Biểu tượng Bluetooth tròn tô màu theo pha kết nối (màn hẹp).
class _CompactBluetooth extends StatelessWidget {
  final BlePhase phase;
  const _CompactBluetooth({required this.phase});

  @override
  Widget build(BuildContext context) {
    final c = ConnectionBadge.colorOf(phase);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Icon(
        phase == BlePhase.connected
            ? Icons.bluetooth_connected_rounded
            : Icons.bluetooth_rounded,
        size: 18,
        color: AppColors.readable(c),
      ),
    );
  }
}
