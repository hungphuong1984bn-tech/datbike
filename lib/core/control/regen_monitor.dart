// Giám sát Regen — CHỈ ĐỌC. Không có đường ghi nào.
//
// Chưa có characteristic nào được xác minh là đọc/ghi mức Regen độc lập (xem
// docs/REGEN_VERIFICATION.md). Mô-đun này chỉ trình bày telemetry thật mà xe
// gửi (điện áp, dòng pha, tốc độ) và công suất suy ra = V × I.
//
// DẤU CỦA DÒNG PHA — ĐÃ KIỂM CHỨNG (02/11/2026, docs/REGEN_VERIFICATION.md §7):
// trên 502 mẫu chạy thật, dòng pha tương quan NGHỊCH với gia tốc (r = −0.77);
// 98% mẫu dòng pha > +2 A đi cùng GIẢM tốc, 84% mẫu < −2 A đi cùng TĂNG tốc.
//   • DƯƠNG  = nạp ngược (regen / phanh tái sinh)
//   • ÂM     = kéo ga (xả pin)
// Khớp chú thích bộ giải mã (bike_log.dart). Câu "âm khi phanh tái sinh" trong
// docs/BLE_PROTOCOL_SPEC.md là SAI. Công suất V×I vì thế cũng DƯƠNG khi nạp.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../proto/bike_log.dart';

@immutable
class RegenReading {
  final double phaseCurrentA;
  final double voltageV;
  final double powerKw; // V × I / 1000, giữ nguyên dấu của dòng pha
  final double speedKmh;

  const RegenReading({
    required this.phaseCurrentA,
    required this.voltageV,
    required this.powerKw,
    required this.speedKmh,
  });
}

/// Trích số liệu từ một gói telemetry. null = không có dữ liệu hợp lệ.
RegenReading? regenReadingFrom(BikeLogMsg? m) {
  if (m == null) return null;
  if (!(m.voltage > 0)) return null; // điện áp không hợp lệ → không suy công suất
  return RegenReading(
    phaseCurrentA: m.phase,
    voltageV: m.voltage,
    powerKw: m.voltage * m.phase / 1000.0,
    speedKmh: m.speed,
  );
}

/// Dòng năng lượng tức thời, theo dấu ĐÃ KIỂM CHỨNG.
enum RegenFlow {
  regen, // dòng pha dương, xe đang chạy → nạp ngược
  traction, // dòng pha âm → kéo ga
  idle, // gần 0 hoặc xe đứng yên
}

/// Ngưỡng phân loại (khớp RegenAnalysis).
const double kRegenFlowMinPhaseA = 3.0;
const double kRegenFlowMinSpeedKmh = 5.0;

RegenFlow classifyRegenFlow(RegenReading? r) {
  if (r == null) return RegenFlow.idle;
  if (r.phaseCurrentA >= kRegenFlowMinPhaseA &&
      r.speedKmh >= kRegenFlowMinSpeedKmh) {
    return RegenFlow.regen;
  }
  if (r.phaseCurrentA <= -kRegenFlowMinPhaseA) return RegenFlow.traction;
  return RegenFlow.idle;
}

@immutable
class RegenPeaks {
  final double? maxKw; // công suất lớn nhất (dương = nạp ngược)
  final double? minKw; // công suất nhỏ nhất (âm = kéo ga)
  final double recoveredWh; // năng lượng thu hồi tích lũy từ lúc reset
  const RegenPeaks({this.maxKw, this.minKw, this.recoveredWh = 0});
}

final regenPeaksProvider =
    NotifierProvider<RegenPeaksNotifier, RegenPeaks>(RegenPeaksNotifier.new);

class RegenPeaksNotifier extends Notifier<RegenPeaks> {
  DateTime? _lastAt;
  double _lastRegenKw = 0;

  @override
  RegenPeaks build() {
    ref.listen<BikeLogMsg?>(bleProvider.select((s) => s.lastTelemetry), (_, m) {
      final r = regenReadingFrom(m);
      if (r == null) return;
      final now = DateTime.now();
      // Tích phân công suất nạp (hình thang). Khoảng trống > 2,5 s không tính.
      var addWh = 0.0;
      final regenKw = classifyRegenFlow(r) == RegenFlow.regen ? r.powerKw : 0.0;
      if (_lastAt != null) {
        final dtMs = now.difference(_lastAt!).inMilliseconds;
        if (dtMs > 0 && dtMs <= 2500) {
          addWh = (regenKw + _lastRegenKw) / 2 * 1000 * dtMs / 3.6e6;
        }
      }
      _lastAt = now;
      _lastRegenKw = regenKw;
      final mx = state.maxKw;
      final mn = state.minKw;
      state = RegenPeaks(
        maxKw: (mx == null || r.powerKw > mx) ? r.powerKw : mx,
        minKw: (mn == null || r.powerKw < mn) ? r.powerKw : mn,
        recoveredWh: state.recoveredWh + addWh,
      );
    });
    return const RegenPeaks();
  }

  void reset() {
    _lastAt = null;
    _lastRegenKw = 0;
    state = const RegenPeaks();
  }
}
