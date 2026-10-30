// Cấu hình đồng hồ lái xe (Cluster): giao diện, ô dữ liệu, màu, cỡ chữ, nền,
// ngày/đêm, nguồn tốc độ, xoay màn hình. Lưu cục bộ bằng SharedPreferences.
// Mặc định: Portrait cố định, không tự xoay ngang.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ClusterTheme { sport, minimal, touring, original }

enum ClusterMetric {
  speed,
  battery,
  odo,
  voltage,
  current,
  power,
  tripDistance,
  tripTime,
  connection,
}

enum NightMode { auto, day, night }

/// Nguồn tốc độ hiển thị chính. BLE = tốc độ xe báo qua Bluetooth, GPS = từ điện thoại.
enum SpeedSource { ble, gps }

extension ClusterThemeLabel on ClusterTheme {
  String get label => switch (this) {
        ClusterTheme.sport => 'Sport',
        ClusterTheme.minimal => 'Minimal',
        ClusterTheme.touring => 'Touring',
        ClusterTheme.original => 'Original',
      };
}

extension ClusterMetricLabel on ClusterMetric {
  String get label => switch (this) {
        ClusterMetric.speed => 'Tốc độ',
        ClusterMetric.battery => 'Pin',
        ClusterMetric.odo => 'ODO',
        ClusterMetric.voltage => 'Điện áp',
        ClusterMetric.current => 'Dòng điện',
        ClusterMetric.power => 'Công suất',
        ClusterMetric.tripDistance => 'Quãng đường',
        ClusterMetric.tripTime => 'Thời gian',
        ClusterMetric.connection => 'Kết nối',
      };
}

class ClusterConfig {
  final ClusterTheme theme;

  /// Thứ tự TẤT CẢ ô dữ liệu (kể cả ô đang ẩn).
  final List<ClusterMetric> order;
  final Set<ClusterMetric> hidden;

  /// Màu nhấn (ARGB). null = dùng màu mặc định của giao diện.
  final int? accent;

  /// Nền tùy chỉnh (ARGB). null = dùng nền mặc định của giao diện.
  final int? background;

  /// Hệ số cỡ chữ 0.8 – 1.4.
  final double fontScale;
  final NightMode nightMode;
  final SpeedSource speedSource;

  /// Cho phép xoay ngang. MẶC ĐỊNH false: khóa Portrait.
  final bool allowRotate;
  final bool keepAwake;
  final bool fullscreen;

  /// Đồng hồ kết hợp bản đồ (bản đồ ở nửa dưới).
  final bool showMap;

  const ClusterConfig({
    this.theme = ClusterTheme.sport,
    this.order = ClusterMetric.values,
    this.hidden = const {},
    this.accent,
    this.background,
    this.fontScale = 1.0,
    this.nightMode = NightMode.auto,
    this.speedSource = SpeedSource.ble,
    this.allowRotate = false,
    this.keepAwake = true,
    this.fullscreen = false,
    this.showMap = false,
  });

  static const ClusterConfig defaults = ClusterConfig();

  List<ClusterMetric> get visible =>
      order.where((m) => !hidden.contains(m)).toList(growable: false);

  ClusterConfig copyWith({
    ClusterTheme? theme,
    List<ClusterMetric>? order,
    Set<ClusterMetric>? hidden,
    int? accent,
    bool clearAccent = false,
    int? background,
    bool clearBackground = false,
    double? fontScale,
    NightMode? nightMode,
    SpeedSource? speedSource,
    bool? allowRotate,
    bool? keepAwake,
    bool? fullscreen,
    bool? showMap,
  }) =>
      ClusterConfig(
        theme: theme ?? this.theme,
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        accent: clearAccent ? null : (accent ?? this.accent),
        background: clearBackground ? null : (background ?? this.background),
        fontScale: (fontScale ?? this.fontScale).clamp(0.8, 1.4).toDouble(),
        nightMode: nightMode ?? this.nightMode,
        speedSource: speedSource ?? this.speedSource,
        allowRotate: allowRotate ?? this.allowRotate,
        keepAwake: keepAwake ?? this.keepAwake,
        fullscreen: fullscreen ?? this.fullscreen,
        showMap: showMap ?? this.showMap,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'theme': theme.name,
        'order': order.map((e) => e.name).toList(),
        'hidden': hidden.map((e) => e.name).toList(),
        if (accent != null) 'accent': accent,
        if (background != null) 'background': background,
        'fontScale': fontScale,
        'nightMode': nightMode.name,
        'speedSource': speedSource.name,
        'allowRotate': allowRotate,
        'keepAwake': keepAwake,
        'fullscreen': fullscreen,
        'showMap': showMap,
      };

  /// Đọc cấu hình; dữ liệu hỏng/thiếu trường → rơi về mặc định từng trường,
  /// không bao giờ ném lỗi làm app không mở được.
  factory ClusterConfig.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final parsedOrder = <ClusterMetric>[];
    final rawOrder = j['order'];
    if (rawOrder is List) {
      for (final n in rawOrder) {
        final m = pick<ClusterMetric>(ClusterMetric.values, n, ClusterMetric.speed);
        if (m.name == n && !parsedOrder.contains(m)) parsedOrder.add(m);
      }
    }
    // Bổ sung ô mới (nếu bản sau thêm ô) vào cuối danh sách.
    for (final m in ClusterMetric.values) {
      if (!parsedOrder.contains(m)) parsedOrder.add(m);
    }

    final parsedHidden = <ClusterMetric>{};
    final rawHidden = j['hidden'];
    if (rawHidden is List) {
      for (final n in rawHidden) {
        final m = pick<ClusterMetric>(ClusterMetric.values, n, ClusterMetric.speed);
        if (m.name == n) parsedHidden.add(m);
      }
    }

    return ClusterConfig(
      theme: pick(ClusterTheme.values, j['theme'], ClusterTheme.sport),
      order: parsedOrder,
      hidden: parsedHidden,
      accent: (j['accent'] as num?)?.toInt(),
      background: (j['background'] as num?)?.toInt(),
      fontScale: ((j['fontScale'] as num?)?.toDouble() ?? 1.0).clamp(0.8, 1.4).toDouble(),
      nightMode: pick(NightMode.values, j['nightMode'], NightMode.auto),
      speedSource: pick(SpeedSource.values, j['speedSource'], SpeedSource.ble),
      allowRotate: j['allowRotate'] == true,
      keepAwake: j['keepAwake'] != false,
      fullscreen: j['fullscreen'] == true,
      showMap: j['showMap'] == true,
    );
  }

  String encode() => jsonEncode(toJson());

  static ClusterConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return ClusterConfig.fromJson(d);
    } catch (_) {}
    return defaults;
  }
}

const String kClusterConfigKey = 'cluster_config_v1';

class ClusterConfigController extends Notifier<ClusterConfig> {
  bool _loaded = false;

  @override
  ClusterConfig build() {
    _load();
    return ClusterConfig.defaults;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ClusterConfig.decode(prefs.getString(kClusterConfigKey));
    } catch (_) {
      // Giữ mặc định nếu không đọc được bộ nhớ.
    }
  }

  Future<void> update(ClusterConfig next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kClusterConfigKey, next.encode());
    } catch (_) {}
  }

  void setTheme(ClusterTheme t) => update(state.copyWith(theme: t));

  void toggleMetric(ClusterMetric m, bool visible) {
    final h = {...state.hidden};
    visible ? h.remove(m) : h.add(m);
    update(state.copyWith(hidden: h));
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [...state.order];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    update(state.copyWith(order: list));
  }

  /// Khôi phục toàn bộ về mặc định, kể cả khóa Portrait.
  Future<void> resetToDefaults() => update(ClusterConfig.defaults);
}

final clusterConfigProvider =
    NotifierProvider<ClusterConfigController, ClusterConfig>(ClusterConfigController.new);
