// Tab "Cài đặt" — hồ sơ chủ xe và menu chức năng chia nhóm rõ ràng:
//   Xe và kết nối · Năng lượng và vận hành · Chẩn đoán và phần mềm · Ứng dụng.
// Mọi mục đều dẫn tới màn hình THẬT có sẵn; không có mục giả.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ble/ble_controller.dart';
import '../battery/battery_diagnostics_screen.dart';
import '../ble_diagnostics/ble_diagnostics_screen.dart';
import '../ota/ota_screen.dart';
import '../scan/scan_screen.dart';
import '../settings/vehicle_settings_screen.dart';
import '../settings/app_settings_screen.dart';
import '../regen/regen_screen.dart';
import '../proximity/proximity_screen.dart';
import '../dashboard_studio/dashboard_studio_screen.dart';
import '../firmware_lab/firmware_lab_screen.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';

class _Item {
  final IconData icon;
  final Color Function() color;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  const _Item(this.icon, this.color, this.title, this.subtitle, this.onTap);
}

void _push(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final name = (ble.userName?.trim().isNotEmpty == true) ? ble.userName!.trim() : null;
    final serial = (ble.frameSerial != null && ble.frameSerial!.isNotEmpty)
        ? ble.frameSerial!
        : (ble.bikeModelCode != null
            ? 'Mẫu xe: ${ble.bikeModelCode}'
            : 'Chưa có số khung — kết nối xe để đọc');

    final groups = <(String, List<_Item>)>[
      (
        'Xe và kết nối',
        [
          _Item(Icons.bluetooth_searching_rounded, () => AppColors.primary, 'Ghép đôi xe mới',
              'Quét và kết nối xe qua Bluetooth', (c) => _push(c, const ScanScreen())),
          _Item(Icons.tune_rounded, () => AppColors.textPrimary, 'Cài đặt xe và phanh',
              'Chế độ lái, giới hạn tốc độ, phanh', (c) => _push(c, const VehicleSettingsScreen())),
          _Item(Icons.sensors_rounded, () => AppColors.primary, 'Mở khóa thông minh / Tự động khóa',
              'Mở và khóa xe theo khoảng cách điện thoại', (c) => _push(c, const ProximityScreen())),
        ]
      ),
      (
        'Năng lượng và vận hành',
        [
          _Item(Icons.bolt_rounded, () => AppColors.amberText, 'Sạc và năng lượng',
              'Phiên sạc, công suất, thời gian còn lại', (c) => Navigator.of(c).pushNamed('/charging')),
          _Item(Icons.speed_rounded, () => AppColors.primary, 'Thông số vận hành',
              'Biểu đồ tốc độ, điện áp, dòng điện, nhiệt độ', (c) => Navigator.of(c).pushNamed('/operations')),
          _Item(Icons.tune_rounded, () => AppColors.primary, 'Trung tâm điều khiển vận hành',
              'Grab, ECE, Regen — điều khiển thủ công, đọc lại từ xe', (c) => Navigator.of(c).pushNamed('/control-center')),
          _Item(Icons.battery_charging_full_rounded, () => AppColors.greenText, 'Phanh tái sinh (Regen)',
              'Giám sát số liệu thu hồi năng lượng (chỉ đọc)', (c) => _push(c, const RegenScreen())),
          _Item(Icons.medical_services_outlined, () => AppColors.greenText, 'Bác sĩ pin và BMS',
              'Điện áp từng cell, cân bằng, cảnh báo', (c) => _push(c, const BatteryDiagnosticsScreen())),
        ]
      ),
      (
        'Chẩn đoán và phần mềm',
        [
          _Item(Icons.health_and_safety_rounded, () => AppColors.red, 'Trung tâm chẩn đoán',
              'Lỗi, lịch sử lỗi, nhật ký hoạt động', (c) => Navigator.of(c).pushNamed('/diagnostics')),
          _Item(Icons.bluetooth_searching_rounded, () => AppColors.primary, 'Chẩn đoán Bluetooth (BLE)',
              'Trạng thái liên kết, gói dữ liệu, bằng chứng giao thức', (c) => _push(c, const BleDiagnosticsScreen())),
          _Item(Icons.receipt_long_rounded, () => AppColors.accentDim, 'Tệp nhật ký Bluetooth',
              'Xem, chia sẻ, xuất nhật ký kỹ thuật', (c) => Navigator.of(c).pushNamed('/logs')),
          _Item(Icons.system_update_rounded, () => AppColors.primary, 'Cập nhật phần mềm (OTA)',
              'Cập nhật phần mềm xe không dây', (c) => _push(c, const OtaScreen())),
          _Item(Icons.science_rounded, () => AppColors.accentDim, 'Phòng thí nghiệm',
              'Công cụ nâng cao, chỉ dành cho người am hiểu', (c) => _push(c, const FirmwareLabScreen())),
        ]
      ),
      (
        'Ứng dụng',
        [
          _Item(Icons.dashboard_customize_rounded, () => AppColors.amberText, 'Xưởng đồng hồ',
              'Thiết kế đồng hồ lái xe của riêng bạn', (c) => _push(c, const DashboardStudioScreen())),
          _Item(Icons.settings_suggest_rounded, () => AppColors.primary, 'Cài đặt ứng dụng',
              'Giao diện, đơn vị, thông báo, thông tin xe, phiên bản', (c) => _push(c, const AppSettingsScreen())),
        ]
      ),
    ];

    return DsScaffold(
      title: 'Cài đặt',
      subtitle: 'Hồ sơ, xe và ứng dụng',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.huge),
        children: [
          // ── Hồ sơ ─────────────────────────────────────────────────────
          GlassCard(
            hero: true,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    name != null ? name[0].toUpperCase() : 'D',
                    style: AppTypography.headlineMd(color: Colors.white),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Xin chào,', style: AppTypography.labelMd()),
                      Text(name ?? 'Chủ xe',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSm(color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(serial,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySm()),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chỉnh sửa hồ sơ',
                  onPressed: () => _showEditProfileDialog(context, ref, ble),
                  icon: Icon(Icons.edit_outlined, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ConnectionBadge(phase: ble.phase),
              const Spacer(),
              if (ble.phase == BlePhase.connected)
                TextButton.icon(
                  onPressed: () => _disconnect(context, ref, ble),
                  icon: Icon(Icons.link_off_rounded, size: 18, color: AppColors.red),
                  label: Text('Ngắt kết nối', style: TextStyle(color: AppColors.redText)),
                ),
            ],
          ),

          // ── Giao diện nhanh ───────────────────────────────────────────
          const DsSectionHeader('Giao diện'),
          const ThemeModeSelector(),

          // ── Các nhóm chức năng ────────────────────────────────────────
          for (final g in groups) ...[
            DsSectionHeader(g.$1),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < g.$2.length; i++) ...[
                    if (i > 0)
                      Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 64),
                    _MenuRow(item: g.$2[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref, BleState ble) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Ngắt kết nối xe?',
      message: 'Ngắt Bluetooth khỏi xe ${ble.bikeName ?? "xe"}? Bạn có thể kết nối lại bất cứ lúc nào.',
      confirmLabel: 'Ngắt kết nối',
      destructive: true,
      icon: Icons.link_off_rounded,
    );
    if (!ok) return;
    await ref.read(bleProvider.notifier).disconnect();
    if (context.mounted) {
      showAppSnack(context, 'Đã ngắt kết nối Bluetooth', kind: SnackKind.success);
    }
  }

  void _showEditProfileDialog(BuildContext context, WidgetRef ref, BleState ble) {
    final userController = TextEditingController(text: ble.userName ?? '');
    final bikeController = TextEditingController(text: ble.bikeName ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Chỉnh Sửa Hồ Sơ',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tên hiển thị chủ xe',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: userController,
                decoration: InputDecoration(
                  hintText: 'Nhập tên của bạn',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tên gọi của xe',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: bikeController,
                decoration: InputDecoration(
                  hintText: 'VD: Dat Bike Quantum S1',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (ble.phase == BlePhase.connected) ...[
                const SizedBox(height: 8),
                Text(
                  '💡 Tên xe sẽ được lưu vào flash xe qua cổng Bluetooth.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.tertiary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'HỦY',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryFill,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newUserName = userController.text.trim();
              final newBikeName = bikeController.text.trim();
              Navigator.pop(ctx);

              if (newUserName.isNotEmpty) {
                await ref.read(bleProvider.notifier).setUserName(newUserName);
              }
              if (newBikeName.isNotEmpty && newBikeName != ble.bikeName) {
                if (ble.phase == BlePhase.connected) {
                  await ref.read(bleProvider.notifier).setFwBikeName(newBikeName);
                } else {
                  await ref.read(bleProvider.notifier).setLocalBikeName(newBikeName);
                }
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Đã cập nhật hồ sơ thành công!', style: GoogleFonts.plusJakartaSans()),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(
              'LƯU HỒ SƠ',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

}

class _MenuRow extends StatelessWidget {
  final _Item item;
  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.color();
    return InkWell(
      onTap: () => item.onTap(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(item.icon, size: 20, color: color),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMd(color: AppColors.textPrimary)),
                    Text(item.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodySm()),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
