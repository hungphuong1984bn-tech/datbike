// Giám sát Regen — CHỈ ĐỌC. Không có đường ghi nào.
//
// Chưa có characteristic nào được xác minh là đọc/ghi mức Regen độc lập (xem
// docs/REGEN_VERIFICATION.md). Mô-đun này chỉ trình bày telemetry thật mà xe
// gửi (điện áp, dòng pha, tốc độ) và công suất suy ra = V × I.
//
// DẤU CỦA DÒNG PHA CHƯA ĐƯỢC KIỂM CHỨNG: bộ giải mã (bike_log.dart) ghi
// "âm khi kéo ga, dương khi tái tạo", còn docs/BLE_PROTOCOL_SPEC.md/REGEN_
// VERIFICATION.md ghi "âm khi phanh tái sinh". Vì vậy app hiển thị giá trị có
// dấu và cả hai cực trị, KHÔNG tự gắn nhãn "đang nạp ngược".

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

@immutable
class RegenPeaks {
  final double? maxKw;
  final double? minKw;
  const RegenPeaks({this.maxKw, this.minKw});
}

final regenPeaksProvider =
    NotifierProvider<RegenPeaksNotifier, RegenPeaks>(RegenPeaksNotifier.new);

class RegenPeaksNotifier extends Notifier<RegenPeaks> {
  @override
  RegenPeaks build() {
    ref.listen<BikeLogMsg?>(bleProvider.select((s) => s.lastTelemetry), (_, m) {
      final r = regenReadingFrom(m);
      if (r == null) return;
      final mx = state.maxKw;
      final mn = state.minKw;
      state = RegenPeaks(
        maxKw: (mx == null || r.powerKw > mx) ? r.powerKw : mx,
        minKw: (mn == null || r.powerKw < mn) ? r.powerKw : mn,
      );
    });
    return const RegenPeaks();
  }

  void reset() => state = const RegenPeaks();
}
