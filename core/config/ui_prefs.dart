// Tuỳ chọn giao diện được lưu cục bộ (SharedPreferences) — khởi động lại app
// không làm mất. Cùng mẫu Notifier với cluster_config.dart.
//
//  • themeModeProvider — Hệ thống / Sáng / Tối (mặc định: theo hệ thống).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kThemeModeKey = 'ui_theme_mode_v1';

ThemeMode themeModeFromName(String? name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

class ThemeModeController extends Notifier<ThemeMode> {
  bool _loaded = false;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = themeModeFromName(prefs.getString(kThemeModeKey));
      if (saved != state) state = saved;
    } catch (_) {
      // Không đọc được bộ nhớ → giữ "theo hệ thống".
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kThemeModeKey, mode.name);
    } catch (_) {}
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
