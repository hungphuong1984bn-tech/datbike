// Battery Hub — nối luồng BatteryLogMsg từ BleController với các engine.
//
// KHÔNG gửi bất kỳ lệnh nào xuống xe/BMS. Chỉ ĐỌC `bleProvider` (lastBattery,
// lastBatteryAt, phase, lastTelemetry) và gọi `fetchBatteryDetails()` — hàm đọc
// sẵn có — khi người dùng bấm làm mới ở UI.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../proto/bike_log.dart';
import 'balancing_monitor.dart';
import 'battery_analytics.dart';
import 'battery_config.dart';
import 'battery_history.dart';
import 'battery_history_store.dart';
import 'battery_sessions.dart';
import 'cell_model.dart';
import 'cell_protection_engine.dart';

class AlertLogEntry {
  final String id;
  final AlertType type;
  final AlertSeverity severity;
  final String title;
  final String measured;
  final List<int> cellIndices;
  final DateTime startedAt;
  final DateTime? clearedAt;

  const AlertLogEntry({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.measured,
    required this.cellIndices,
    required this.startedAt,
    this.clearedAt,
  });

  bool get isActive => clearedAt == null;

  AlertLogEntry cleared(DateTime at) => AlertLogEntry(
        id: id,
        type: type,
        severity: severity,
        title: title,
        measured: measured,
        cellIndices: cellIndices,
        startedAt: startedAt,
        clearedAt: at,
      );
}

class BatteryHubState {
  final PackSnapshot? latest;
  final BmsFreshness freshness;
  final bool connected;
  final ProtectionReport report;
  final BalancingState balancing;
  final List<BalancingEvent> balancingEvents;
  final List<ActivitySession> activitySessions;
  final List<AlertLogEntry> alertLog;
  final BatteryConfig config;

  /// Tăng mỗi khi có gói BMS mới được nạp — UI dùng để vẽ lại biểu đồ lịch sử.
  final int revision;

  /// Tổng số gói BMS đã nhận trong phiên.
  final int packetCount;

  const BatteryHubState({
    required this.latest,
    required this.freshness,
    required this.connected,
    required this.report,
    required this.balancing,
    required this.balancingEvents,
    required this.activitySessions,
    required this.alertLog,
    required this.config,
    required this.revision,
    required this.packetCount,
  });

  factory BatteryHubState.initial({required bool connected}) => BatteryHubState(
        latest: null,
        freshness: BmsFreshness.none,
        connected: connected,
        report: ProtectionReport.empty(DateTime.now()),
        balancing: BalancingState.unknown,
        balancingEvents: const [],
        activitySessions: const [],
        alertLog: const [],
        config: BatteryConfig.defaults,
        revision: 0,
        packetCount: 0,
      );

  BatteryHubState copyWith({
    PackSnapshot? latest,
    BmsFreshness? freshness,
    bool? connected,
    ProtectionReport? report,
    BalancingState? balancing,
    List<BalancingEvent>? balancingEvents,
    List<ActivitySession>? activitySessions,
    List<AlertLogEntry>? alertLog,
    BatteryConfig? config,
    int? revision,
    int? packetCount,
  }) =>
      BatteryHubState(
        latest: latest ?? this.latest,
        freshness: freshness ?? this.freshness,
        connected: connected ?? this.connected,
        report: report ?? this.report,
        balancing: balancing ?? this.balancing,
        balancingEvents: balancingEvents ?? this.balancingEvents,
        activitySessions: activitySessions ?? this.activitySessions,
        alertLog: alertLog ?? this.alertLog,
        config: config ?? this.config,
        revision: revision ?? this.revision,
        packetCount: packetCount ?? this.packetCount,
      );

  CellSnapshot? cellAt(int i) => latest?.cellAt(i);
}

class BatteryHub extends Notifier<BatteryHubState> {
  static const Duration _tickEvery = Duration(seconds: 2);
  static const int _maxAlertLog = 100;

  /// Telemetry chỉ được dùng khi đã nhận trong khoảng này so với gói BMS.
  static const Duration _telemetryMaxAge = Duration(seconds: 6);

  final BatteryHistory history = BatteryHistory();
  // Lịch sử bền vững (mẫu thưa, chỉ từ gói BMS thật còn mới). Không bị xóa bởi "Đặt lại phiên".
  final BatteryHistoryStore _store = BatteryHistoryStore();
  final BatteryHistorySampler _sampler = BatteryHistorySampler();
  final BalancingMonitor _balancing = BalancingMonitor();
  final ActivityTracker _activity = ActivityTracker();

  Timer? _timer;
  BatteryLogMsg? _lastMsg;
  DateTime? _lastAt;
  Map<String, DateTime> _alertSince = <String, DateTime>{};

  @override
  BatteryHubState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(_tickEvery, (_) => _tick());

    ref.listen<DateTime?>(
      bleProvider.select((s) => s.lastBatteryAt),
      (_, _) => sync(),
    );
    ref.listen<BlePhase>(
      bleProvider.select((s) => s.phase),
      (_, _) => _tick(),
    );

    final connected = ref.read(bleProvider).phase == BlePhase.connected;
    Future<void>.microtask(() async {
      final cfg = await BatteryConfigStore.load();
      _applyConfig(cfg, persist: false);
      sync();
    });
    return BatteryHubState.initial(connected: connected);
  }

  bool get _connected => ref.read(bleProvider).phase == BlePhase.connected;

  /// Đồng bộ với gói BMS mới nhất trong BleState (idempotent).
  void sync() {
    final ble = ref.read(bleProvider);
    final msg = ble.lastBattery;
    final at = ble.lastBatteryAt;
    if (msg == null || at == null) {
      _tick();
      return;
    }
    if (identical(msg, _lastMsg)) {
      _tick();
      return;
    }
    ingest(msg, at);
  }

  /// Nạp một gói BMS thật. Công khai để có thể kiểm thử và để UI gọi sync().
  void ingest(BatteryLogMsg msg, DateTime at) {
    if (_lastAt != null && !at.isAfter(_lastAt!)) return;
    _lastMsg = msg;
    _lastAt = at;

    final snap = BatteryAnalytics.analyze(msg, at, cfg: state.config);
    final now = DateTime.now();
    final live = BmsFreshness.evaluate(
          receivedAt: at,
          now: now,
          connected: _connected,
        ) ==
        BmsFreshness.live;

    history.add(snap);

    if (live) {
      _balancing.onPack(snap);
      if (_sampler.shouldRecord(at)) {
        unawaited(_store.append(BatteryHistoryRecord.fromSnapshot(snap)));
      }
      final ble = ref.read(bleProvider);
      final tele = _freshTelemetry(ble, at);
      double? soc = snap.socPercent > 0 ? snap.socPercent : null;
      soc ??= tele != null ? tele.percent.toDouble() : null;
      _activity.onSample(
        at: at,
        phaseA: tele?.phase,
        packV: snap.packVoltage,
        soc: soc,
      );
    }

    _publish(now, pack: snap, bumpRevision: true);
  }

  BikeLogMsg? _freshTelemetry(BleState ble, DateTime around) {
    final tele = ble.lastTelemetry;
    final teleAt = ref.read(bleProvider.notifier).lastTelemetryAt;
    if (tele == null || teleAt == null) return null;
    return teleAt.difference(around).abs() <= _telemetryMaxAge ? tele : null;
  }

  void _tick() {
    _publish(DateTime.now());
  }

  void _publish(DateTime now, {PackSnapshot? pack, bool bumpRevision = false}) {
    final ble = ref.read(bleProvider);
    final connected = ble.phase == BlePhase.connected;
    final latest = pack ?? state.latest;

    final freshness = BmsFreshness.evaluate(
      receivedAt: latest?.receivedAt,
      now: now,
      connected: connected,
    );

    if (freshness != BmsFreshness.live && freshness != BmsFreshness.none) {
      if (_balancing.ongoing != null || _balancing.state != BalancingState.unknown) {
        _balancing.onLinkLost(now);
      }
      if (freshness == BmsFreshness.lost) _activity.onLinkLost(now);
    }

    final teleTemp = (() {
      final tele = _freshTelemetry(ble, latest?.receivedAt ?? now);
      return tele != null && tele.bmsTemp > 0 ? tele.bmsTemp : null;
    })();

    final report = CellProtectionEngine.evaluate(
      pack: latest,
      now: now,
      connected: connected,
      cfg: state.config,
      telemetryBmsTempC: teleTemp,
      trends: history.trends(state.config.trendMinSamples),
      activeSince: _alertSince,
    );

    final log = _updateAlertLog(report, now);
    _alertSince = {for (final a in report.alerts) a.id: a.since};

    final next = state.copyWith(
      latest: latest,
      freshness: freshness,
      connected: connected,
      report: report,
      balancing: _balancing.state,
      balancingEvents: _balancing.events,
      activitySessions: _activity.sessions,
      alertLog: log,
      revision: bumpRevision ? state.revision + 1 : state.revision,
      packetCount: bumpRevision ? state.packetCount + 1 : state.packetCount,
    );

    if (bumpRevision || _meaningfulChange(state, next)) {
      state = next;
    }
  }

  bool _meaningfulChange(BatteryHubState a, BatteryHubState b) {
    if (a.freshness != b.freshness ||
        a.connected != b.connected ||
        a.balancing != b.balancing ||
        a.report.overall != b.report.overall ||
        a.report.alerts.length != b.report.alerts.length ||
        a.alertLog.length != b.alertLog.length ||
        a.activitySessions.length != b.activitySessions.length ||
        a.balancingEvents.length != b.balancingEvents.length ||
        !identical(a.config, b.config)) {
      return true;
    }
    for (var i = 0; i < a.report.alerts.length; i++) {
      final x = a.report.alerts[i];
      final y = b.report.alerts[i];
      if (x.id != y.id || x.severity != y.severity || x.measured != y.measured) {
        return true;
      }
    }
    return false;
  }

  List<AlertLogEntry> _updateAlertLog(ProtectionReport report, DateTime now) {
    final log = List<AlertLogEntry>.of(state.alertLog);
    final activeIds = {for (final a in report.alerts) a.id};

    for (var i = 0; i < log.length; i++) {
      final e = log[i];
      if (e.isActive && !activeIds.contains(e.id)) {
        log[i] = e.cleared(now);
      }
    }
    for (final a in report.alerts) {
      final open = log.any((e) => e.isActive && e.id == a.id);
      if (!open) {
        log.add(AlertLogEntry(
          id: a.id,
          type: a.type,
          severity: a.severity,
          title: a.title,
          measured: a.measured,
          cellIndices: a.cellIndices,
          startedAt: a.since,
        ));
      }
    }
    if (log.length > _maxAlertLog) {
      log.removeRange(0, log.length - _maxAlertLog);
    }
    return log;
  }

  // ── Cấu hình ─────────────────────────────────────────────────────────────
  /// Trả về thông báo lỗi nếu cấu hình không hợp lệ, null nếu đã áp dụng.
  Future<String?> updateConfig(BatteryConfig cfg) async {
    final err = cfg.validate();
    if (err != null) return err;
    _applyConfig(cfg, persist: true);
    return null;
  }

  Future<void> resetConfig() async {
    await BatteryConfigStore.reset();
    _applyConfig(BatteryConfig.defaults, persist: false);
  }

  void _applyConfig(BatteryConfig cfg, {required bool persist}) {
    if (persist) {
      unawaited(BatteryConfigStore.save(cfg));
    }
    state = state.copyWith(config: cfg);
    // Phân tích lại gói mới nhất với ngưỡng mới (không thêm vào lịch sử).
    final msg = _lastMsg;
    final at = _lastAt;
    if (msg != null && at != null) {
      final snap = BatteryAnalytics.analyze(msg, at, cfg: cfg);
      _publish(DateTime.now(), pack: snap, bumpRevision: true);
    } else {
      _tick();
    }
  }

  /// Xoá lịch sử phiên (không ảnh hưởng kết nối BLE hay cấu hình).
  void resetSession() {
    history.clear();
    _balancing.clear();
    _activity.clear();
    _alertSince = <String, DateTime>{};
    state = state.copyWith(
      balancingEvents: const [],
      activitySessions: const [],
      alertLog: const [],
      balancing: BalancingState.unknown,
      revision: state.revision + 1,
    );
    _tick();
  }

  /// Yêu cầu đọc lại nhật ký pin — dùng hàm đọc sẵn có của BleController.
  Future<void> requestRefresh() async {
    await ref.read(bleProvider.notifier).fetchBatteryDetails();
    sync();
  }
}

final batteryHubProvider =
    NotifierProvider<BatteryHub, BatteryHubState>(BatteryHub.new);
