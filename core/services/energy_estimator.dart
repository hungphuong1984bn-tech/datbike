// Ước tính tiêu hao pin và chọn điểm sạc dọc tuyến. Toàn bộ là hàm thuần.
//
// QUY TẮC TRUNG THỰC: mọi con số ở đây là ƯỚC TÍNH. Kết quả luôn kèm `basis`
// (dựa trên cái gì) để UI nói rõ cho người dùng; không có dữ liệu thì trả null
// thay vì bịa số.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'charging_station_service.dart';

/// Một chuyến đã hoàn tất: quãng đường và % pin đã dùng.
class TripSample {
  final double distanceKm;
  final int usedPercent;
  const TripSample(this.distanceKm, this.usedPercent);
}

class ConsumptionEstimate {
  /// % pin tiêu hao trên mỗi km.
  final double percentPerKm;

  /// Nguồn của ước tính, hiển thị cho người dùng.
  final String basis;
  final bool fromHistory;
  final int samples;
  const ConsumptionEstimate(this.percentPerKm, this.basis, this.fromHistory, this.samples);
}

class EnergyEstimator {
  EnergyEstimator._();

  /// Ưu tiên lịch sử chuyến đi thật (trung vị của tối đa 10 chuyến gần nhất,
  /// chỉ tính chuyến ≥ 2 km và đã dùng ≥ 2% pin để tránh nhiễu làm tròn).
  /// Không có lịch sử → dùng "pin hiện tại / km còn lại" do xe tự báo.
  /// Không có gì → null.
  static ConsumptionEstimate? estimate({
    required List<TripSample> history,
    int? percent,
    double? kmLeft,
  }) {
    final ppk = <double>[
      for (final t in history.take(10))
        if (t.distanceKm >= 2.0 && t.usedPercent >= 2 && t.usedPercent <= 100) t.usedPercent / t.distanceKm,
    ]..sort();
    if (ppk.isNotEmpty) {
      final mid = ppk.length ~/ 2;
      final median = ppk.length.isOdd ? ppk[mid] : (ppk[mid - 1] + ppk[mid]) / 2;
      return ConsumptionEstimate(median, 'trung vị ${ppk.length} chuyến gần nhất của bạn', true, ppk.length);
    }
    if (percent != null && percent > 0 && kmLeft != null && kmLeft > 1) {
      return ConsumptionEstimate(percent / kmLeft, 'xe báo còn ~${kmLeft.toStringAsFixed(0)} km với $percent% pin', false, 0);
    }
    return null;
  }

  static double batteryAfter(double currentPercent, double distanceKm, double percentPerKm) =>
      currentPercent - distanceKm * percentPerKm;

  /// Quãng đường tối đa còn đi được trước khi chạm mức dự phòng.
  static double rangeKm(double currentPercent, double reservePercent, double percentPerKm) =>
      math.max(0, (currentPercent - reservePercent) / percentPerKm);
}

class ChargeStop {
  final ChargingStation station;

  /// Quãng đường dọc tuyến từ điểm xuất phát tới điểm gần trạm nhất (km).
  final double alongKm;

  /// Khoảng cách từ tuyến tới trạm (km) — đoạn đường vòng một chiều.
  final double offsetKm;

  /// % pin ước tính khi tới trạm.
  final double batteryAtArrival;
  const ChargeStop(this.station, this.alongKm, this.offsetKm, this.batteryAtArrival);
}

class ChargePlanner {
  ChargePlanner._();

  static const Distance _dist = Distance();

  /// Cần sạc dọc đường không? (pin đến đích dự kiến thấp hơn mức dự phòng)
  static bool needsCharging({
    required double startPercent,
    required double totalKm,
    required double percentPerKm,
    double reservePercent = 15,
  }) =>
      EnergyEstimator.batteryAfter(startPercent, totalKm, percentPerKm) < reservePercent;

  /// Chọn trạm nằm gần tuyến, tới được với pin ≥ mức dự phòng, và XA NHẤT dọc
  /// tuyến (tận dụng tối đa pin trước khi sạc). Null nếu không có trạm nào thỏa.
  static ChargeStop? pickStop({
    required List<LatLng> route,
    required List<ChargingStation> stations,
    required double startPercent,
    required double percentPerKm,
    double reservePercent = 15,
    double maxOffsetKm = 3.0,
  }) {
    if (route.length < 2 || stations.isEmpty || percentPerKm <= 0) return null;

    final cum = List<double>.filled(route.length, 0);
    for (var i = 1; i < route.length; i++) {
      cum[i] = cum[i - 1] + _dist.as(LengthUnit.Kilometer, route[i - 1], route[i]);
    }

    ChargeStop? best;
    for (final s in stations) {
      var nearestIdx = 0;
      var nearestKm = double.infinity;
      for (var i = 0; i < route.length; i++) {
        final d = _dist.as(LengthUnit.Kilometer, route[i], s.position);
        if (d < nearestKm) {
          nearestKm = d;
          nearestIdx = i;
        }
      }
      if (nearestKm > maxOffsetKm) continue;
      final along = cum[nearestIdx];
      final batt = EnergyEstimator.batteryAfter(startPercent, along + nearestKm, percentPerKm);
      if (batt < reservePercent) continue;
      if (best == null || along > best.alongKm) {
        best = ChargeStop(s, along, nearestKm, batt);
      }
    }
    return best;
  }
}
