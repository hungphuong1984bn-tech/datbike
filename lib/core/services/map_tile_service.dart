import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'offline_map_service.dart';

enum MapTileStyle {
  fastCdn,     // OSM-FR: Máy chủ OpenStreetMap hiệu năng cao, đa luồng subdomain a/b/c, hoàn toàn miễn phí & KHÔNG CẦN API KEY
  darkEv,      // Dark EV: Lớp bản đồ đêm công nghệ bằng bộ lọc đảo màu HUD (No API Key)
  cyclosm,     // CyclOSM: Bản đồ chuyên biệt cho xe 2 bánh / xe điện Dat Bike (No API Key)
  osmStandard, // OpenStreetMap tiêu chuẩn (No API Key)
}

class MapTileService {
  /// Nhà cung cấp tile do bạn chọn, truyền lúc build — KHÔNG ghi khóa vào mã nguồn:
  ///   flutter build apk --dart-define=TILE_URL_TEMPLATE=https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=KHOA
  /// Khi đặt, mọi kiểu bản đồ (trừ CyclOSM) dùng nguồn này thay cho máy chủ cộng đồng OSM-FR.
  /// Nên dùng nhà cung cấp có chính sách sử dụng rõ ràng (MapTiler, Stadia, Thunderforest…) hoặc tự dựng
  /// khi lượng người dùng lớn.
  static const String customTileTemplate = String.fromEnvironment('TILE_URL_TEMPLATE');

  /// Mã nhận diện nhà cung cấp tùy chỉnh để hiện ghi công đúng (vd. "© MapTiler © OpenStreetMap").
  static const String customAttribution = String.fromEnvironment('TILE_ATTRIBUTION');

  static bool get hasCustomProvider => customTileTemplate.isNotEmpty;

  /// Matrix đảo màu và xoay hệ màu để biến bản đồ OSM tiêu chuẩn thành bản đồ đêm Dark EV
  /// Tương thích 100% mọi thiết bị, không cần API Key, không phụ thuộc server bên thứ ba
  static const List<double> darkMatrix = <double>[
    -0.574, -1.430, -0.144, 0, 255,
    -0.426, -0.570, -0.144, 0, 255,
    -0.426, -1.430,  0.856, 0, 255,
     0,      0,      0,      1,   0,
  ];

  static TileLayer buildTileLayer({
    MapTileStyle style = MapTileStyle.fastCdn,
    void Function(Object error)? onTileError,
  }) {
    final errCb = onTileError == null ? null : (dynamic tile, Object error, StackTrace? stack) => onTileError(error);
    if (hasCustomProvider && style != MapTileStyle.cyclosm) {
      final dark = style == MapTileStyle.darkEv;
      return TileLayer(
        urlTemplate: customTileTemplate,
        userAgentPackageName: 'vn.mybike.mybike_app',
        maxZoom: 20,
        tileProvider: OfflineCacheTileProvider(),
        errorTileCallback: errCb,
        tileBuilder: dark
            ? (context, tileWidget, tile) => ColorFiltered(
                  colorFilter: const ColorFilter.matrix(darkMatrix),
                  child: tileWidget,
                )
            : null,
      );
    }
    // Tự động kiểm tra bộ nhớ đệm ổ cứng local offline trước (0ms latency, chạy offline hoàn toàn)
    // Nếu chưa có thì tải từ mạng và tự động lưu vào ổ cứng
    final offlineProvider = OfflineCacheTileProvider();

    switch (style) {
      case MapTileStyle.fastCdn:
        return TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'vn.mybike.mybike_app',
          maxZoom: 20,
          tileProvider: offlineProvider,
          errorTileCallback: errCb,
        );

      case MapTileStyle.darkEv:
        return TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'vn.mybike.mybike_app',
          maxZoom: 20,
          tileProvider: offlineProvider,
          errorTileCallback: errCb,
          tileBuilder: (context, tileWidget, tile) {
            return ColorFiltered(
              colorFilter: const ColorFilter.matrix(darkMatrix),
              child: tileWidget,
            );
          },
        );

      case MapTileStyle.cyclosm:
        return TileLayer(
          urlTemplate: 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'vn.mybike.mybike_app',
          maxZoom: 20,
          tileProvider: offlineProvider,
          errorTileCallback: errCb,
        );

      case MapTileStyle.osmStandard:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'vn.mybike.mybike_app',
          maxZoom: 19,
          tileProvider: offlineProvider,
          errorTileCallback: errCb,
        );
    }
  }

  static String getStyleName(MapTileStyle style) {
    switch (style) {
      case MapTileStyle.fastCdn:
        return 'Tải Nhanh (OSM-FR)';
      case MapTileStyle.darkEv:
        return 'Bản Đồ Đêm EV';
      case MapTileStyle.cyclosm:
        return 'Làn Xe Máy / 2 Bánh';
      case MapTileStyle.osmStandard:
        return 'OSM Tiêu Chuẩn';
    }
  }

  static IconData getStyleIcon(MapTileStyle style) {
    switch (style) {
      case MapTileStyle.fastCdn:
        return Icons.bolt_rounded;
      case MapTileStyle.darkEv:
        return Icons.dark_mode_rounded;
      case MapTileStyle.cyclosm:
        return Icons.two_wheeler_rounded;
      case MapTileStyle.osmStandard:
        return Icons.public_rounded;
    }
  }
}
