// Screen 4: User Profile — Hồ sơ Chủ Xe Máy Điện Dat Bike
// Thiết kế tham chiếu Geely "Edit your personalized information" tinh chỉnh cho Dat Bike:
// - Icon QR (quét mã ghép nối NFC / BLE xe máy) & Chat hỗ trợ Dat Care 24/7.
// - Avatar tròn đen chữ J (hoặc D).
// - Lời chào lớn Hello, Dat Bike User (font rộng), ID DB-QUANTUM-0187, nút Edit Profile ->.
// - Danh sách cài đặt thiết thực cho xe máy điện trên nền trắng:
//     1. Cài đặt xe & Chế độ lái (Regen Braking, Giới hạn tốc độ)
//     2. Bác Sĩ Pin & Chẩn đoán 24-Cell BMS
//     3. Cập nhật phần mềm xe qua mạng (OTA Firmware)
//     4. Thông tin ứng dụng (About)
//     5. Đăng xuất (Log Out)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ble/ble_controller.dart';
import '../battery/battery_diagnostics_screen.dart';
import '../ota/ota_screen.dart';
import '../scan/scan_screen.dart';
import '../settings/vehicle_settings_screen.dart';
import '../regen/regen_screen.dart';
import '../logs/logs_screen.dart';
import '../firmware_lab/firmware_lab_screen.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ══════════════════════════════════════════════════════════════
              // 1. THANH TRẠNG THÁI TIÊU ĐỀ & PHÍM TẮT TÌM XE BLE
              // ══════════════════════════════════════════════════════════════
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TÀI KHOẢN & XE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primarySoftBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bluetooth_searching_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Tìm Xe BLE',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ══════════════════════════════════════════════════════════════
              // 2. AVATAR CHỦ XE DAT BIKE (CHỮ CÁI ĐẦU TIÊN TỪ TÊN)
              // ══════════════════════════════════════════════════════════════
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  (ble.userName?.trim().isNotEmpty == true)
                      ? ble.userName!.trim()[0].toUpperCase()
                      : 'D',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ══════════════════════════════════════════════════════════════
              // 3. LỜI CHÀO LỚN Hello, [Tên chủ xe]
              // ══════════════════════════════════════════════════════════════
              Text(
                'Hello,\n${(ble.userName?.trim().isNotEmpty == true) ? ble.userName!.trim() : "Dat Bike User"}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 10),

              // 4. MÃ ĐỊNH DANH XE MÁY ĐIỆN: SERIAL KHUNG / MODEL / TRẠNG THÁI
              Text(
                (ble.frameSerial != null && ble.frameSerial!.isNotEmpty)
                    ? ble.frameSerial!
                    : (ble.bikeModelCode != null
                        ? 'Model: ${ble.bikeModelCode}'
                        : 'Chưa đồng bộ số khung (Kết nối xe để đọc)'),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(height: 14),

              // 5. NÚT Edit Profile -> Mở hộp thoại chỉnh sửa
              InkWell(
                onTap: () => _showEditProfileDialog(context, ref, ble),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Chỉnh sửa hồ sơ',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ══════════════════════════════════════════════════════════════
              // 5b. GIAO DIỆN — Hệ thống / Sáng / Tối (lưu bền)
              // ══════════════════════════════════════════════════════════════
              Text(
                'Giao diện',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const ThemeModeSelector(),
              const SizedBox(height: 4),
              Text(
                'Chế độ "Hệ thống" tự đổi Sáng/Tối theo điện thoại.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),

              Text(
                'Xe, pin & dữ liệu',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              // ══════════════════════════════════════════════════════════════
              // 6. DANH SÁCH CÀI ĐẶT THIẾT YẾU CHO XE MÁY ĐIỆN TRÊN NỀN TRẮNG
              // ══════════════════════════════════════════════════════════════
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.panelBorder),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  children: [
                    // 0. Quản lý xe & Ghép đôi xe Dat Bike
                    _profileListItem(
                      icon: Icon(Icons.bluetooth_searching_rounded, size: 22, color: AppColors.primary),
                      title: 'Ghép đôi xe mới',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ScanScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 1. Cài đặt xe & Phanh tái sinh
                    _profileListItem(
                      icon: Icon(Icons.tune_rounded, size: 22, color: AppColors.textPrimary),
                      title: 'Cài đặt xe & Phanh',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const VehicleSettingsScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 1a. Sạc & Năng lượng (trước đây là tab riêng)
                    _profileListItem(
                      icon: Icon(Icons.bolt_rounded, size: 22, color: AppColors.amberText),
                      title: 'Sạc & Năng lượng',
                      onTap: () => Navigator.of(context).pushNamed('/charging'),
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 1b. Regen (phanh tái sinh) — mô-đun có kiểm soát
                    _profileListItem(
                      icon: Icon(Icons.battery_charging_full_rounded, size: 22, color: AppColors.greenText),
                      title: 'Phanh tái sinh (Regen)',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RegenScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 2. Bác Sĩ Pin & Chẩn đoán 24-Cell BMS
                    _profileListItem(
                      icon: const Icon(Icons.medical_services_outlined, size: 22, color: AppColors.tertiary),
                      title: 'Bác sĩ pin & BMS',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const BatteryDiagnosticsScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 3. Cập nhật phần mềm xe qua mạng (OTA)
                    _profileListItem(
                      icon: Icon(Icons.system_update_rounded, size: 22, color: AppColors.primary),
                      title: 'Cập nhật phần mềm (OTA)',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const OtaScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 4. Nhật ký BLE & Xuất Log
                    _profileListItem(
                      icon: const Icon(Icons.receipt_long_rounded, size: 22, color: Color(0xFF6366F1)),
                      title: 'Nhật ký Bluetooth',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LogsScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 5. Phòng Kiểm Nghiệm Firmware Lab
                    _profileListItem(
                      icon: const Icon(Icons.science_rounded, size: 22, color: Color(0xFF8B5CF6)),
                      title: 'Phòng thí nghiệm Lab',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const FirmwareLabScreen()),
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 6. Thông tin ứng dụng (About)
                    _profileListItem(
                      icon: Icon(Icons.info_outline_rounded, size: 22, color: AppColors.textPrimary),
                      title: 'Thông tin ứng dụng',
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Dat Bike Companion',
                          applicationVersion: 'v2.2.0 (Phase 2)',
                          applicationIcon: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/images/bike_logo_3d.png',
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(Icons.two_wheeler_rounded, size: 36, color: AppColors.primary),
                            ),
                          ),
                          children: [
                            Text(
                              'Ứng dụng điều khiển xe máy điện Dat Bike (Quantum & Weaver series) tối ưu hóa kết nối BLE và quản lý thông số pin thông minh.',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13),
                            ),
                          ],
                        );
                      },
                    ),

                    Divider(color: AppColors.panelBorder, height: 1, thickness: 1, indent: 56, endIndent: 20),

                    // 7. Ngắt kết nối xe
                    _profileListItem(
                      icon: const Icon(Icons.link_off_rounded, size: 22, color: AppColors.red),
                      title: 'Ngắt kết nối xe',
                      onTap: () {
                        () async {
                          final ok = await showConfirmDialog(
                            context,
                            title: 'Ngắt kết nối xe?',
                            message:
                                'Ngắt Bluetooth khỏi xe ${ble.bikeName ?? "Dat Bike"}? Bạn có thể kết nối lại bất cứ lúc nào.',
                            confirmLabel: 'Ngắt kết nối',
                            destructive: true,
                            icon: Icons.link_off_rounded,
                          );
                          if (!ok) return;
                          await ref.read(bleProvider.notifier).disconnect();
                          if (context.mounted) {
                            showAppSnack(context, 'Đã ngắt kết nối Bluetooth', kind: SnackKind.success);
                          }
                        }();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
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

  Widget _profileListItem({
    required Widget icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Center(child: icon),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
