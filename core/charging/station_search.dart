// Lọc / sắp xếp trạm sạc và đánh giá khả năng tới trạm bằng pin. Toàn bộ là
// hàm thuần (không I/O) để kiểm thử được.

import 'package:latlong2/latlong.dart';

import '../services/charging_station_service.dart';
import '../services/energy_estimator.dart';

/// Hệ số đường thực tế so với đường chim bay (ước lượng, chỉ khi chưa có tuyến).
const double kDetourFactor = 1.3;

/// Mức pin dự phòng khi tới nơi.
const double kReservePercent = 15;

class StationFilter {
  /// null = tất cả khu vực.
  final double? radiusKm;

  /// Từ khóa: tên trạm, địa chỉ, nhà vận hành, tỉnh/thành (khớp chuỗi thật trong dữ liệu).
  final String query;

  /// Chuẩn đầu nối cần có (so khớp với mô tả ổ cắm của nguồn). Rỗng = không lọc.
  final String connector;

  /// Công suất tối thiểu (kW). Trạm KHÔNG có dữ liệu công suất bị loại khi > 0.
  final double minPowerKw;

  /// Chỉ trạm có giờ mở ghi rõ 24/7.
  final bool only24h;

  /// Hiện trạm chưa rõ loại xe (kèm cảnh báo, không tính là dùng được).
  final bool includeUnknownVehicle;

  /// Hiện cả trạm chỉ dành cho ô tô (đánh dấu "không dành cho xe máy").
  final bool includeCarOnly;

  /// Ẩn trạm đã đóng cửa.
  final bool hideClosed;

  const StationFilter({
    this.radiusKm = 10,
    this.query = '',
    this.connector = '',
    this.minPowerKw = 0,
    this.only24h = false,
    this.includeUnknownVehicle = true,
    this.includeCarOnly = false,
    this.hideClosed = true,
  });

  StationFilter copyWith({
    Object? radiusKm = _keep,
    String? query,
    String? connector,
    double? minPowerKw,
    bool? only24h,
    bool? includeUnknownVehicle,
    bool? includeCarOnly,
    bool? hideClosed,
  }) =>
      StationFilter(
        radiusKm: identical(radiusKm, _keep) ? this.radiusKm : radiusKm as double?,
        query: query ?? this.query,
        connector: connector ?? this.connector,
        minPowerKw: minPowerKw ?? this.minPowerKw,
        only24h: only24h ?? this.only24h,
        includeUnknownVehicle: includeUnknownVehicle ?? this.includeUnknownVehicle,
        includeCarOnly: includeCarOnly ?? this.includeCarOnly,
        hideClosed: hideClosed ?? this.hideClosed,
      );

  static const Object _keep = Object();

  /// Số bộ lọc nâng cao đang bật (để hiện huy hiệu).
  int get advancedCount =>
      (connector.isNotEmpty ? 1 : 0) +
      (minPowerKw > 0 ? 1 : 0) +
      (only24h ? 1 : 0) +
      (includeCarOnly ? 1 : 0) +
      (!includeUnknownVehicle ? 1 : 0);
}

class StationHit {
  final ChargingStation station;

  /// Khoảng cách chim bay (km); null khi chưa có vị trí tham chiếu.
  final double? km;
  const StationHit(this.station, this.km);
}

class StationSearch {
  StationSearch._();

  static const Distance _d = Distance();

  static String _norm(String s) => s.toLowerCase().trim();

  static bool matchesQuery(ChargingStation s, String q) {
    final n = _norm(q);
    if (n.isEmpty) return true;
    final hay = _norm('${s.name} ${s.operator ?? ''} ${s.address ?? ''}');
    return n.split(RegExp(r'\s+')).every(hay.contains);
  }

  /// Lọc rồi sắp xếp gần → xa. [origin] null → không tính khoảng cách / bán kính.
  /// Trạm hợp lệ cho xe máy luôn xếp trước trạm "chưa rõ loại xe" và trạm ô tô.
  static List<StationHit> apply(
    List<ChargingStation> all,
    StationFilter f, {
    LatLng? origin,
  }) {
    final hits = <StationHit>[];
    for (final s in all) {
      if (f.hideClosed && s.status == StationStatus.closed) continue;
      if (s.carOnly && !f.includeCarOnly) continue;
      if (s.vehicle == VehicleSupport.unknown && !f.includeUnknownVehicle) continue;
      if (!matchesQuery(s, f.query)) continue;
      if (f.connector.isNotEmpty && !_norm(s.sockets ?? '').contains(_norm(f.connector))) continue;
      if (f.minPowerKw > 0 && (s.powerKw == null || s.powerKw! < f.minPowerKw)) continue;
      if (f.only24h && _norm(s.openingHours ?? '') != '24/7') continue;
      final km = origin == null ? null : _d.as(LengthUnit.Kilometer, origin, s.position);
      if (f.radiusKm != null && km != null && km > f.radiusKm!) continue;
      hits.add(StationHit(s, km));
    }
    int rank(ChargingStation s) => s.supportsMotorbike ? 0 : (s.carOnly ? 2 : 1);
    hits.sort((a, b) {
      final r = rank(a.station).compareTo(rank(b.station));
      if (r != 0) return r;
      if (a.km == null || b.km == null) return a.station.name.compareTo(b.station.name);
      return a.km!.compareTo(b.km!);
    });
    return hits;
  }

  /// Các chuẩn đầu nối có thật trong dữ liệu đã tải (để dựng bộ lọc, không bịa).
  static List<String> availableConnectors(List<ChargingStation> all) {
    final set = <String>{};
    for (final s in all) {
      for (final part in (s.sockets ?? '').split(',')) {
        final m = RegExp(r'^\s*([^×]+)').firstMatch(part);
        final name = m?.group(1)?.trim() ?? '';
        if (name.isNotEmpty) set.add(name);
      }
    }
    return set.toList()..sort();
  }
}

enum ReachLevel { unknown, likely, tight, risky, unlikely }

class ReachAssessment {
  final ReachLevel level;

  /// % pin ước tính khi tới trạm; null khi không đủ dữ liệu.
  final double? batteryAtArrival;

  /// Cơ sở tính (hiển thị cho người dùng).
  final String basis;
  const ReachAssessment(this.level, this.batteryAtArrival, this.basis);

  String get label => switch (level) {
        ReachLevel.unknown => 'Chưa đủ dữ liệu để ước tính',
        ReachLevel.likely => 'Nhiều khả năng đủ pin',
        ReachLevel.tight => 'Sát mức pin dự phòng',
        ReachLevel.risky => 'Có thể không đủ để giữ pin dự phòng',
        ReachLevel.unlikely => 'Nhiều khả năng KHÔNG đủ pin',
      };
}

class ReachEstimator {
  ReachEstimator._();

  /// [percent] CHỈ truyền khi có khung telemetry mới từ BMS/xe; null → unknown.
  /// [routeKm] null → dùng chim bay × [kDetourFactor] và nói rõ trong cơ sở.
  /// Kết quả luôn là ước tính: không bao giờ khẳng định chắc chắn tới nơi.
  static ReachAssessment assess({
    required double straightKm,
    double? routeKm,
    int? percent,
    ConsumptionEstimate? consumption,
  }) {
    if (percent == null) {
      return const ReachAssessment(
        ReachLevel.unknown,
        null,
        'Không có % pin trực tiếp từ xe (chưa kết nối hoặc dữ liệu đã cũ).',
      );
    }
    if (consumption == null) {
      return ReachAssessment(
        ReachLevel.unknown,
        null,
        'Pin hiện tại $percent% nhưng chưa có dữ liệu tiêu hao để ước tính.',
      );
    }
    final km = routeKm ?? straightKm * kDetourFactor;
    final after = EnergyEstimator.batteryAfter(percent.toDouble(), km, consumption.percentPerKm);
    final level = after < 0
        ? ReachLevel.unlikely
        : after < kReservePercent
            ? ReachLevel.risky
            : after < kReservePercent + 10
                ? ReachLevel.tight
                : ReachLevel.likely;
    final route = routeKm != null
        ? 'tuyến ${routeKm.toStringAsFixed(1)} km'
        : 'chim bay ×$kDetourFactor ≈ ${km.toStringAsFixed(1)} km';
    return ReachAssessment(
      level,
      after,
      'Pin $percent% · $route · tiêu hao ${consumption.percentPerKm.toStringAsFixed(2)} %/km '
      '(${consumption.basis}). Chưa tính dốc, gió, tải trọng, tốc độ.',
    );
  }
}
