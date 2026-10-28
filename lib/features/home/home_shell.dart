// Shell chính — 3 Tabs Chuẩn Ngôn Ngữ Thiết Kế Xe Máy Điện Dat Bike:
// [ Xe ] · [ Năng Lượng ] · [ Chủ Xe ]

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../charging/charging_screen.dart';
import '../profile/profile_screen.dart';
import '../../ui/geely_icons.dart';
import 'my_bike_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: IndexedStack(
        index: _tab.clamp(0, 2),
        children: const [
          MyBikeScreen(),
          ChargingScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
          boxShadow: [
            BoxShadow(color: Color(0x060F172A), blurRadius: 12, offset: Offset(0, -4)),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          height: 64,
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFFEFF6FF),
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? const Color(0xFF2563EB) : const Color(0xFF64748B),
            ),
          ),
          destinations: [
            NavigationDestination(
              icon: GeelyIcons.bike(size: 22, color: const Color(0xFF64748B)),
              selectedIcon: GeelyIcons.bike(size: 22, color: const Color(0xFF2563EB)),
              label: 'Xe',
            ),
            NavigationDestination(
              icon: GeelyIcons.charging(size: 22, color: const Color(0xFF64748B)),
              selectedIcon: GeelyIcons.charging(size: 22, color: const Color(0xFF2563EB)),
              label: 'Năng Lượng',
            ),
            NavigationDestination(
              icon: GeelyIcons.profile(size: 22, color: const Color(0xFF64748B)),
              selectedIcon: GeelyIcons.profile(size: 22, color: const Color(0xFF2563EB)),
              label: 'Chủ Xe',
            ),
          ],
        ),
      ),
    );
  }
}
