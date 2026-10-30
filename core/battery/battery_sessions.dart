// Lịch sử sạc / xả của phiên chạy hiện tại.
//
// Hướng dòng điện lấy từ telemetry xe (BikeLogMsg.phase) vì quy ước dấu của nó đã
// được xác minh trong dự án (DƯƠNG = dòng sạc vào pin, ÂM = xả — xem
// test/battery_and_charging_test.dart). Dấu của BatteryLogMsg.current CHƯA được xác
// minh nên không dùng để suy ra hướng sạc/xả.

enum PackActivity {
  charging('Đang sạc'),
  discharging('Đang xả'),
  idle('Nghỉ');

  final String label;
  const PackActivity(this.label);
}

class ActivitySession {
  final PackActivity activity;
  final DateTime start;
  final DateTime? end;
  final double? startSoc;
  final double? endSoc;
  final double startPackV;
  final double endPackV;
  final double peakCurrentA;

  const ActivitySession({
    required this.activity,
    required this.start,
    this.end,
    this.startSoc,
    this.endSoc,
    required this.startPackV,
    required this.endPackV,
    required this.peakCurrentA,
  });

  bool get isOngoing => end == null;
  Duration durationUntil(DateTime now) => (end ?? now).difference(start);

  ActivitySession copyWith({
    DateTime? end,
    double? endSoc,
    double? endPackV,
    double? peakCurrentA,
  }) =>
      ActivitySession(
        activity: activity,
        start: start,
        end: end ?? this.end,
        startSoc: startSoc,
        endSoc: endSoc ?? this.endSoc,
        startPackV: startPackV,
        endPackV: endPackV ?? this.endPackV,
        peakCurrentA: peakCurrentA ?? this.peakCurrentA,
      );
}

class ActivityTracker {
  /// Dòng tối thiểu (A) để coi là đang sạc/xả thay vì nghỉ.
  static const double idleBandA = 0.5;
  static const Duration minRecordDuration = Duration(seconds: 20);
  static const int maxSessions = 30;

  final List<ActivitySession> _done = <ActivitySession>[];
  ActivitySession? _open;

  ActivitySession? get ongoing => _open;

  List<ActivitySession> get sessions {
    final out = <ActivitySession>[];
    if (_open != null) out.add(_open!);
    out.addAll(_done.reversed);
    return List<ActivitySession>.unmodifiable(out);
  }

  static PackActivity classify(double phaseA) {
    if (phaseA > idleBandA) return PackActivity.charging;
    if (phaseA < -idleBandA) return PackActivity.discharging;
    return PackActivity.idle;
  }

  /// [phaseA] null = không có telemetry trực tiếp → không ghi nhận gì.
  void onSample({
    required DateTime at,
    required double? phaseA,
    required double packV,
    double? soc,
  }) {
    if (phaseA == null || !phaseA.isFinite) return;
    final act = classify(phaseA);

    final cur = _open;
    if (cur != null && cur.activity == act) {
      final abs = phaseA.abs();
      _open = cur.copyWith(
        endPackV: packV,
        endSoc: soc,
        peakCurrentA: abs > cur.peakCurrentA ? abs : cur.peakCurrentA,
      );
      return;
    }
    if (cur != null) _closeOpen(at, packV, soc);

    if (act != PackActivity.idle) {
      _open = ActivitySession(
        activity: act,
        start: at,
        startSoc: soc,
        endSoc: soc,
        startPackV: packV,
        endPackV: packV,
        peakCurrentA: phaseA.abs(),
      );
    }
  }

  /// Mất dữ liệu: đóng phiên đang mở tại thời điểm cho trước.
  void onLinkLost(DateTime at) {
    if (_open != null) _closeOpen(at, _open!.endPackV, _open!.endSoc);
  }

  void clear() {
    _done.clear();
    _open = null;
  }

  void _closeOpen(DateTime at, double packV, double? soc) {
    final closed = _open!.copyWith(end: at, endPackV: packV, endSoc: soc);
    _open = null;
    if (closed.durationUntil(at) >= minRecordDuration) {
      _done.add(closed);
      if (_done.length > maxSessions) {
        _done.removeRange(0, _done.length - maxSessions);
      }
    }
  }
}
