// Shell chính — thanh điều hướng dưới (thao tác một tay) với 5 mục, mỗi mục là
// một module THẬT của app (không có trang giả):
//
//   Tổng quan · Bản đồ · Bác sĩ Pin · Nhật ký · Cài đặt
//
// Các chức năng còn lại vẫn truy cập được như trước:
//   • Cockpit HUD   — nút lớn ở Tổng quan (và biểu tượng đồng hồ ở thanh tiêu đề)
//   • Kết nối xe    — chip trạng thái ở Tổng quan, mục "Ghép đôi xe" ở Cài đặt
//   • Năng lượng/Sạc — lối tắt ở Tổng quan và mục ở Cài đặt
//
// Hiệu năng/pin: chỉ tab Tổng quan được giữ sống; các tab khác chỉ dựng khi
// đang xem và được huỷ khi rời đi — nên luồng GPS của Bản đồ hay việc đọc file
// của Nhật ký không chạy ngầm khi người dùng ở màn khác.

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../battery/battery_diagnostics_screen.dart';
import '../logs/logs_screen.dart';
import '../navigation/charge_finder_screen.dart';
import '../profile/profile_screen.dart';
import 'my_bike_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _NavItem(this.label, this.icon, this.selectedIcon);
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _items = <_NavItem>[
    _NavItem('Tổng quan', Icons.dashboard_outlined, Icons.dashboard_rounded),
    _NavItem('Bản đồ', Icons.map_outlined, Icons.map_rounded),
    _NavItem(
      'Bác sĩ Pin',
      Icons.battery_charging_full_outlined,
      Icons.battery_charging_full_rounded,
    ),
    _NavItem(
      'Nhật ký',
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
    ),
    _NavItem('Cài đặt', Icons.settings_outlined, Icons.settings_rounded),
  ];

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const MyBikeScreen();
      case 1:
        return const ChargeFinderScreen();
      case 2:
        return const BatteryDiagnosticsScreen();
      case 3:
        return const LogsScreen();
      default:
        return const ProfileScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Back ở tab khác → về Tổng quan; ở Tổng quan → thoát như thường.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < _items.length; i++)
              (i == 0 || i == _tab) ? _page(i) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.panel,
            border: Border(
              top: BorderSide(color: AppColors.panelBorderBright, width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              for (final it in _items)
                NavigationDestination(
                  icon: Icon(it.icon),
                  selectedIcon: Icon(it.selectedIcon),
                  label: it.label,
                  tooltip: it.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
