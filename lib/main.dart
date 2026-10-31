// THBIKE — ứng dụng điều khiển & giám sát xe điện.
// Không có đăng nhập: mở app là thấy xe. Phase 1 = kết nối ổn định + dashboard
// + OTA metadata; Phase 2 = session handshake + lệnh điều khiển + OTA BLE.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/ble/ble_logger.dart';
import 'features/scan/scan_screen.dart';
import 'features/scan/connecting_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/battery/battery_diagnostics_screen.dart';
import 'features/charging/charging_screen.dart';
import 'features/operations/operations_screen.dart';
import 'features/settings/vehicle_settings_screen.dart';
import 'features/control_center/control_center_screen.dart';
import 'features/regen/regen_screen.dart';
import 'features/home/home_shell.dart';
import 'features/cluster/cluster_screen.dart';
import 'features/proximity/proximity_screen.dart';
import 'features/dashboard_studio/dashboard_studio_screen.dart';
import 'features/dashboard_studio/dashboard_live_screen.dart';
import 'features/navigation/charge_finder_screen.dart';
import 'core/charging/charge_provider.dart';
import 'core/telemetry/ops_provider.dart';
import 'core/config/cluster_config.dart';
import 'core/config/ui_prefs.dart';
import 'features/logs/logs_screen.dart';
import 'features/diagnostics/diagnostics_screen.dart';
import 'features/settings/app_settings_screen.dart';
import 'core/diagnostics/diag_provider.dart';
import 'features/firmware_lab/firmware_lab_screen.dart';
import 'ui/app_theme.dart';
import 'core/brand/app_info.dart';
import 'features/about/about_screen.dart';
import 'features/splash/splash_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Bắt toàn bộ lỗi chưa xử lý → ghi ra ble_logs/app_errors.jsonl (xem qua
  // màn Logs). Lỗi framework (build widget) và lỗi async/uncaught đều được
  // ghi kèm stack trace, không phụ thuộc session BLE.
  FlutterError.onError = (details) {
    BleLogger.logAppError('flutter_error', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    BleLogger.logAppError('uncaught_error', error, stackTrace);
    return true; // đã ghi log — chặn crash trắng màn hình
  };

  // Khóa Portrait ngay từ lúc khởi động. Chỉ mở xoay khi người dùng bật
  // "Cho phép xoay ngang" trong cài đặt đồng hồ (xem MyBikeApp).
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: MyBikeApp()));
}

class MyBikeApp extends ConsumerStatefulWidget {
  const MyBikeApp({super.key});

  @override
  ConsumerState<MyBikeApp> createState() => _MyBikeAppState();
}

class _MyBikeAppState extends ConsumerState<MyBikeApp> with WidgetsBindingObserver {
  // ThemeData dựng một lần, tránh tạo lại mỗi khi cấu hình đồng hồ thay đổi.
  late final ThemeData _lightTheme = AppTheme.light();
  late final ThemeData _darkTheme = AppTheme.dark();

  Brightness _effective(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Áp palette trước khung hình đầu tiên để không nháy sai màu.
    AppColors.apply(_effective(ref.read(themeModeProvider)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Hệ thống đổi sáng/tối (vd. đặt lịch tự động) → theo nếu đang ở "Hệ thống".
  @override
  void didChangePlatformBrightness() {
    _applyTheme(ref.read(themeModeProvider));
  }

  /// Đổi palette rồi ép dựng lại TOÀN BỘ cây widget (không tạo lại → giữ state,
  /// stack điều hướng, kết nối BLE). Cần thiết vì phần lớn widget cũ đọc
  /// AppColors.* trực tiếp thay vì qua Theme.of(context).
  void _applyTheme(ThemeMode mode) {
    if (!AppColors.apply(_effective(mode))) return;
    if (!mounted) return;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ThemeMode>(themeModeProvider, (_, mode) => _applyTheme(mode));
    ref.listen<bool>(
      clusterConfigProvider.select((c) => c.allowRotate),
      (_, allow) => SystemChrome.setPreferredOrientations(
        allow
            ? DeviceOrientation.values
            : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      ),
    );
    // Nạp cấu hình đã lưu ngay khi app mở (để biết người dùng có bật xoay không).
    ref.watch(clusterConfigProvider);
    // Giữ bộ ghi phiên sạc chạy nền (chỉ đọc telemetry); select hằng số nên không làm dựng lại gốc.
    ref.watch(chargeProvider.select((_) => 0));
    ref.watch(opsProvider.select((_) => 0)); // ghi lịch sử vận hành nền cho biểu đồ
    ref.watch(diagProvider.select((_) => 0)); // ghi lịch sử lỗi/nhật ký chẩn đoán nền (chỉ đọc)
    final mode = ref.watch(themeModeProvider);
    AppColors.apply(_effective(mode)); // đảm bảo khớp ngay cả ở lần dựng đầu

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: mode,
      builder: (context, child) {
        final dark = AppColors.isDark;
        // Icon thanh trạng thái/điều hướng hệ thống tương phản với nền.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppColors.panel,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: ThBikeSplashOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeShell(),
        '/scan': (_) => const ScanScreen(),
        '/connecting': (_) => const ConnectingScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/cluster': (_) => const ClusterScreen(),
        '/proximity': (_) => const ProximityScreen(),
        '/studio': (_) => const DashboardStudioScreen(),
        '/dash-live': (_) => const DashboardLiveScreen(),
        '/charge-finder': (_) => const ChargeFinderScreen(),
        '/battery': (_) => const BatteryDiagnosticsScreen(),
        '/charging': (_) => const ChargingScreen(),
        '/operations': (_) => const OperationsScreen(),
        '/settings': (_) => const VehicleSettingsScreen(),
        '/regen': (_) => const RegenScreen(),
        '/control-center': (_) => const ControlCenterScreen(),
        '/logs': (_) => const LogsScreen(),
        '/diagnostics': (_) => const DiagnosticsScreen(),
        '/app-settings': (_) => const AppSettingsScreen(),
        '/lab': (_) => const FirmwareLabScreen(),
        '/about': (_) => const AboutScreen(),
      },
    );
  }
}
