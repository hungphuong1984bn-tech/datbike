// Connecting — Màn chuyển tiếp kết nối BLE (Kinetic Stitch EV).

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/ble/connect_diagnostics.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets.dart';

class ConnectingScreen extends ConsumerStatefulWidget {
  const ConnectingScreen({super.key});

  @override
  ConsumerState<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<ConnectingScreen> {
  String _detail = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _doConnect());
  }

  Future<void> _doConnect() async {
    final args = ModalRoute.of(context)?.settings.arguments
        as Map<String, dynamic>?;
    final device = args?['device'] as BluetoothDevice?;
    final name = args?['name'] as String?;
    if (device == null) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/scan');
      return;
    }
    setState(() => _detail = 'Đang mở phiên GATT & xác thực…');
    try {
      await ref.read(bleProvider.notifier).connect(device, name: name);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      // Hiện đúng bước/loại lỗi (không gộp thành "kết nối thất bại"). Chi tiết
      // kỹ thuật đã nằm trong báo cáo chẩn đoán ở thư mục ble_logs.
      final msg = e is ConnectFailure
          ? '${e.userMessage}\n[${e.stage.name} · ${e.kind.name}'
              '${e.code != null ? ' · mã ${e.code}' : ''}]'
          : 'Lỗi kết nối: $e';
      setState(() => _detail = msg);
      await Future.delayed(const Duration(seconds: 6));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/scan');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        backgroundColor: AppColors.panelSecondary,
                      ),
                    ),
                    Icon(
                      Icons.electric_moped_rounded,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  ble.bikeName ?? 'Xe điện',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _detail.isEmpty ? 'Đang khởi tạo kết nối Bluetooth bảo mật…' : _detail,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 36),
                Panel(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'LƯU Ý KHI KẾT NỐI',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.05 * 12,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '• Đưa điện thoại lại gần xe trong bán kính 2 mét\n'
                        '• Bật chìa khóa hoặc bấm nút mở xe\n'
                        '• Kiểm tra không có thiết bị khác đang chiếm kết nối',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textDim,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
