// Theo dõi phiên sạc từ telemetry THẬT của xe — thuần Dart, không phụ thuộc UI/BLE.
//
// Nguyên tắc "không dữ liệu giả":
//  • Năng lượng nạp (Wh) = tích phân công suất đo được theo thời gian; đoạn mất
//    dữ liệu dài hơn [maxGap] KHÔNG được cộng bù.
//  • Thời gian còn lại ưu tiên số do bộ sạc báo (etaSec). Khi bộ sạc không báo,
//    chỉ ước tính theo tốc độ tăng SOC THỰC TẾ vừa đo (cần đủ mẫu), tuyệt đối
//    không dùng dung lượng/công suất danh định giả định.

import '../battery/battery_history.dart' show Series;

class ChargeSample {
  final DateTime at;
  final double powerW;
  final double voltage;
  final double currentA;
  final double? soc; // %
  final double? tempC;

  const ChargeSample({
    required this.at,
    required this.powerW,
    required this.voltage,
    required this.currentA,
    this.soc,
    this.tempC,
  });
}

class ChargeSession {
  final DateTime start;
  final DateTime? end;
  final double? startSoc;
  final double? endSoc;
  final double energyWh;
  final double peakPowerW;
  final double peakCurrentA;
  final double? maxTempC;

  /// Tổng thời gian mất dữ liệu trong phiên (không tính vào năng lượng).
  final int gapSeconds;

  const ChargeSession({
    required this.start,
    this.end,
    this.startSoc,
    this.endSoc,
    this.energyWh = 0,
    this.peakPowerW = 0,
    this.peakCurrentA = 0,
    this.maxTempC,
    this.gapSeconds = 0,
  });

  bool get isOngoing => end == null;

  Duration durationUntil(DateTime now) => (end ?? now).difference(start);

  double? get socGain =>
      (startSoc != null && endSoc != null) ? endSoc! - startSoc! : null;

  ChargeSession copyWith({
    DateTime? end,
    double? endSoc,
    double? energyWh,
    double? peakPowerW,
    double? peakCurrentA,
    double? maxTempC,
    int? gapSeconds,
  }) =>
      ChargeSession(
        start: start,
        end: end ?? this.end,
        startSoc: startSoc,
        endSoc: endSoc ?? this.endSoc,
        energyWh: energyWh ?? this.energyWh,
        peakPowerW: peakPowerW ?? this.peakPowerW,
        peakCurrentA: peakCurrentA ?? this.peakCurrentA,
        maxTempC: maxTempC ?? this.maxTempC,
        gapSeconds: gapSeconds ?? this.gapSeconds,
      );

  Map<String, Object?> toJson() => {
        's': start.millisecondsSinceEpoch,
        'e': end?.millisecondsSinceEpoch,
        'ss': startSoc,
        'es': endSoc,
        'wh': energyWh,
        'pp': peakPowerW,
        'pa': peakCurrentA,
        'mt': maxTempC,
        'g': gapSeconds,
      };

  static ChargeSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = raw['s'];
    if (s is! num) return null;
    double? d(String k) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    final e = raw['e'];
    return ChargeSession(
      start: DateTime.fromMillisecondsSinceEpoch(s.toInt()),
      end: e is num ? DateTime.fromMillisecondsSinceEpoch(e.toInt()) : null,
      startSoc: d('ss'),
      endSoc: d('es'),
      energyWh: d('wh') ?? 0,
      peakPowerW: d('pp') ?? 0,
      peakCurrentA: d('pa') ?? 0,
      maxTempC: d('mt'),
      gapSeconds: (raw['g'] is num) ? (raw['g'] as num).toInt() : 0,
    );
  }
}

/// Kết quả ước tính thời gian còn lại, kèm nguồn để UI ghi nhãn trung thực.
enum EtaSource {
  /// Bộ sạc của xe báo trực tiếp.
  charger('Bộ sạc báo'),

  /// Suy ra từ tốc độ tăng SOC đo được trong phiên này.
  measuredRate('Ước tính theo tốc độ sạc đo được');

  final String label;
  const EtaSource(this.label);
}

class EtaEstimate {
  final Duration remaining;
  final EtaSource source;
  const EtaEstimate(this.remaining, this.source);
}

class ChargeTracker {
  static const double idleBandA = 0.5;
  static const Duration minRecordDuration = Duration(seconds: 60);
  static const Duration maxGap = Duration(seconds: 15);
  static const Duration endDebounce = Duration(seconds: 20);
  static const Duration chartInterval = Duration(seconds: 2);
  static const int maxSessions = 20;
  static const int chartCapacity = 450; // ≈ 15 phút ở 2 giây/mẫu

  /// Điều kiện ước tính theo tốc độ: đủ thời gian và đủ phần trăm tăng.
  static const Duration rateMinSpan = Duration(minutes: 2);
  static const double rateMinGainPct = 2.0;
  static const Duration rateWindow = Duration(minutes: 10);

  final List<ChargeSession> _done = <ChargeSession>[];
  ChargeSession? _open;
  ChargeSample? _last;
  DateTime? _notChargingSince;
  DateTime? _lastChartAt;
  final List<(DateTime, double)> _socPoints = <(DateTime, double)>[];

  final Series power = Series(chartCapacity);
  final Series voltage = Series(chartCapacity);
  final Series current = Series(chartCapacity);
  final Series soc = Series(chartCapacity);

  ChargeSession? get ongoing => _open;
  ChargeSample? get lastSample => _last;

  /// Mới nhất trước.
  List<ChargeSession> get history =>
      List<ChargeSession>.unmodifiable(_done.reversed);

  /// Nạp lịch sử đã lưu (đã đóng) khi khởi động.
  void restore(Iterable<ChargeSession> sessions) {
    _done
      ..clear()
      ..addAll(sessions.where((s) => !s.isOngoing));
    _done.sort((a, b) => a.start.compareTo(b.start));
    if (_done.length > maxSessions) {
      _done.removeRange(0, _done.length - maxSessions);
    }
  }

  /// [charging] do phía gọi quyết định (bộ sạc báo có mặt hoặc dòng sạc > ngưỡng).
  void onSample({
    required DateTime at,
    required bool charging,
    required double powerW,
    required double voltage,
    required double currentA,
    double? soc,
    double? tempC,
  }) {
    if (!powerW.isFinite || !voltage.isFinite || !currentA.isFinite) return;

    if (!charging) {
      final cur = _open;
      if (cur == null) return;
      _notChargingSince ??= at;
      if (at.difference(_notChargingSince!) >= endDebounce) {
        _close(_notChargingSince!);
      }
      return;
    }
    _notChargingSince = null;

    final sample = ChargeSample(
      at: at,
      powerW: powerW < 0 ? 0 : powerW,
      voltage: voltage,
      currentA: currentA,
      soc: soc,
      tempC: tempC,
    );

    var cur = _open;
    if (cur == null) {
      cur = ChargeSession(
        start: at,
        startSoc: soc,
        endSoc: soc,
        peakPowerW: sample.powerW,
        peakCurrentA: currentA.abs(),
        maxTempC: tempC,
      );
      _open = cur;
      _socPoints.clear();
      power.clear();
      this.voltage.clear();
      current.clear();
      this.soc.clear();
      _lastChartAt = null;
    } else {
      final prev = _last;
      var energy = cur.energyWh;
      var gap = cur.gapSeconds;
      if (prev != null) {
        final dt = at.difference(prev.at);
        if (dt <= maxGap && !dt.isNegative) {
          energy += (prev.powerW + sample.powerW) / 2 * dt.inMilliseconds / 3600000.0;
        } else if (dt > maxGap) {
          gap += dt.inSeconds;
        }
      }
      cur = cur.copyWith(
        endSoc: soc,
        energyWh: energy,
        gapSeconds: gap,
        peakPowerW:
            sample.powerW > cur.peakPowerW ? sample.powerW : cur.peakPowerW,
        peakCurrentA: currentA.abs() > cur.peakCurrentA
            ? currentA.abs()
            : cur.peakCurrentA,
        maxTempC: (tempC != null && (cur.maxTempC == null || tempC > cur.maxTempC!))
            ? tempC
            : cur.maxTempC,
      );
      _open = cur;
    }
    _last = sample;

    if (soc != null) {
      _socPoints.add((at, soc));
      final cutoff = at.subtract(rateWindow);
      while (_socPoints.length > 1 && _socPoints.first.$1.isBefore(cutoff)) {
        _socPoints.removeAt(0);
      }
    }

    if (_lastChartAt == null || at.difference(_lastChartAt!) >= chartInterval) {
      _lastChartAt = at;
      power.add(at, sample.powerW);
      this.voltage.add(at, voltage);
      current.add(at, currentA);
      if (soc != null) this.soc.add(at, soc);
    }
  }

  /// Mất dữ liệu / ngắt kết nối: đóng phiên tại mẫu cuối đã nhận.
  void onLinkLost() {
    if (_open == null) return;
    _close(_last?.at ?? _open!.start);
  }

  void clearHistory() => _done.clear();

  /// Ước tính thời gian còn lại tới đầy. null = chưa đủ dữ liệu thật.
  EtaEstimate? eta({required int chargerEtaSec, required double? currentSoc}) {
    if (_open == null) return null;
    if (chargerEtaSec > 0) {
      return EtaEstimate(Duration(seconds: chargerEtaSec), EtaSource.charger);
    }
    if (currentSoc == null || currentSoc >= 100) return null;
    if (_socPoints.length < 2) return null;
    final first = _socPoints.first;
    final last = _socPoints.last;
    final span = last.$1.difference(first.$1);
    final gain = last.$2 - first.$2;
    if (span < rateMinSpan || gain < rateMinGainPct) return null;
    final pctPerSec = gain / span.inSeconds;
    if (pctPerSec <= 0) return null;
    final secs = ((100 - currentSoc) / pctPerSec).round();
    return EtaEstimate(Duration(seconds: secs), EtaSource.measuredRate);
  }

  void _close(DateTime at) {
    final cur = _open!;
    _open = null;
    _notChargingSince = null;
    _last = null;
    _socPoints.clear();
    final closed = cur.copyWith(end: at);
    if (closed.durationUntil(at) >= minRecordDuration) {
      _done.add(closed);
      if (_done.length > maxSessions) {
        _done.removeRange(0, _done.length - maxSessions);
      }
    }
  }
}
