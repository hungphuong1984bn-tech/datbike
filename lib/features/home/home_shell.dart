// Shell chính — thanh điều hướng dưới (thao tác một tay) với 5 mục, mỗi mục là
// một module THẬT của app (không có trang giả):
//
//   Tổng quan · Trạm sạc · Bác sĩ Pin · Chẩn đoán · Cài đặt
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
import 'package:flutter/services.dart';

import '../../ui/app_theme.dart';
import '../battery/battery_diagnostics_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
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

class _HomeShellState extends State<HomeShell> with SingleTickerProviderStateMixin {
  int _tab = 0;

  // Hiệu ứng chuyển tab: mờ dần + trượt rất nhẹ (ngắn, không tốn hiệu năng).
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppMotion.normal,
    value: 1.0,
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _anim, curve: AppMotion.curve);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_fade);

  static const _items = <_NavItem>[
    _NavItem('Tổng quan', Icons.dashboard_outlined, Icons.dashboard_rounded),
    _NavItem('Trạm sạc', Icons.ev_station_outlined, Icons.ev_station_rounded),
    _NavItem(
      'Bác sĩ Pin',
      Icons.battery_charging_full_outlined,
      Icons.battery_charging_full_rounded,
    ),
    _NavItem(
      'Chẩn đoán',
      Icons.health_and_safety_outlined,
      Icons.health_and_safety_rounded,
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
        return const DiagnosticsScreen();
      default:
        return const ProfileScreen();
    }
  }

  void _select(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
    _anim.forward(from: 0.0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back ở tab khác → về Tổng quan; ở Tổng quan → thoát như thường.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: IndexedStack(
              index: _tab,
              children: [
                for (var i = 0; i < _items.length; i++)
                  (i == 0 || i == _tab) ? _page(i) : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _DsNavBar(
          items: _items,
          selected: _tab,
          onSelect: _select,
        ),
      ),
    );
  }
}

/// Thanh điều hướng dưới: nền bán trong suốt, viên thuốc chỉ thị tab đang chọn
/// có hiệu ứng trượt ngắn; vùng chạm ≥ 48dp; có nhãn đọc màn hình.
class _DsNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const _DsNavBar({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: AppColors.isDark ? 0.96 : 0.98),
        border: Border(
          top: BorderSide(color: AppColors.panelBorderBright, width: 1),
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.navBarHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _DsNavButton(
                    item: items[i],
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DsNavButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DsNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              width: selected ? 56 : 40,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: AppColors.isDark ? 0.22 : 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: AppMotion.fast,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 24,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              style: AppTypography.labelSm(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ).copyWith(letterSpacing: 0),
              child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
