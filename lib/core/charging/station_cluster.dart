// Gom nhóm Marker (clustering) và lọc theo vùng nhìn thấy — hàm thuần, không
// phụ thuộc Flutter nên kiểm thử được và chạy nhanh với hàng nghìn trạm.
//
// Thuật toán: chia màn hình thành lưới ô vuông [cellPx] pixel ở mức zoom hiện
// tại (hệ Web Mercator), mỗi ô một cụm. Ở zoom ≥ [maxClusterZoom] không gom nữa.
// Phần tử "ghim" (đang chọn, đang chỉ đường) luôn hiện riêng, không bị gom.

import 'dart:math' as math;

class ClusterItem<T> {
  final T item;
  final double lat;
  final double lng;
  final bool pinned;
  const ClusterItem(this.item, this.lat, this.lng, {this.pinned = false});
}

class Cluster<T> {
  final double lat;
  final double lng;
  final List<ClusterItem<T>> members;
  const Cluster(this.lat, this.lng, this.members);

  int get count => members.length;
  bool get isSingle => members.length == 1;
  ClusterItem<T> get first => members.first;
}

class GeoBox {
  final double south;
  final double west;
  final double north;
  final double east;
  const GeoBox(this.south, this.west, this.north, this.east);

  /// Nới rộng [frac] (0.2 = 20% mỗi cạnh) để marker sát mép không bị chớp tắt khi kéo.
  GeoBox padded(double frac) {
    final dLat = (north - south) * frac;
    final dLng = (east - west) * frac;
    return GeoBox(south - dLat, west - dLng, north + dLat, east + dLng);
  }

  bool contains(double lat, double lng) => lat >= south && lat <= north && lng >= west && lng <= east;
}

class StationClusterer {
  StationClusterer._();

  /// Từ zoom này trở lên mọi trạm hiện riêng lẻ.
  static const int maxClusterZoom = 16;

  static double _px(double lng, double zoom) => (lng + 180.0) / 360.0 * 256.0 * math.pow(2, zoom);

  static double _py(double lat, double zoom) {
    final c = lat.clamp(-85.0511, 85.0511).toDouble();
    final s = math.sin(c * math.pi / 180.0);
    final y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    return y * 256.0 * math.pow(2, zoom);
  }

  /// Lọc phần tử nằm trong [box] (null = không lọc) rồi gom nhóm.
  static List<Cluster<T>> cluster<T>(
    List<ClusterItem<T>> items, {
    required double zoom,
    GeoBox? box,
    double cellPx = 56,
    int maxZoomToCluster = maxClusterZoom,
  }) {
    final out = <Cluster<T>>[];
    final cells = <String, List<ClusterItem<T>>>{};
    final noCluster = zoom >= maxZoomToCluster;
    for (final it in items) {
      if (box != null && !it.pinned && !box.contains(it.lat, it.lng)) continue;
      if (noCluster || it.pinned) {
        out.add(Cluster<T>(it.lat, it.lng, [it]));
        continue;
      }
      final cx = (_px(it.lng, zoom) / cellPx).floor();
      final cy = (_py(it.lat, zoom) / cellPx).floor();
      (cells['$cx:$cy'] ??= <ClusterItem<T>>[]).add(it);
    }
    for (final members in cells.values) {
      if (members.length == 1) {
        out.add(Cluster<T>(members.first.lat, members.first.lng, members));
        continue;
      }
      var sLat = 0.0, sLng = 0.0;
      for (final m in members) {
        sLat += m.lat;
        sLng += m.lng;
      }
      out.add(Cluster<T>(sLat / members.length, sLng / members.length, members));
    }
    return out;
  }
}
