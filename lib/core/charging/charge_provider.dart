// Nối telemetry xe (bleProvider, CHỈ ĐỌC) với ChargeTracker.
// Không gửi lệnh nào xuống xe. Lịch sử phiên đã đóng được lưu bằng SharedPreferences.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_controller.dart';
import '../proto/bike_log.dart';
import 'charge_session.dart';

class ChargeState {
  final int revision;
  final ChargeSession? ongoing;
  final List<ChargeSession> history;
  final DateTime? lastSampleAt;

  const ChargeState({
    this.revision = 0,
    this.ongoing,
    this.history = const [],
    this.lastSampleAt,
  });
}

class ChargeCenter extends Notifier<ChargeState> {
  static const String _prefsKey = 'charge_sessions_v1';

  /// Quá thời gian này không có mẫu mới thì coi là mất dữ liệu và đóng phiên.
  static const Duration _staleAfter = Duration(seconds: 20);

  /// Công suất sạc: ưu tiên số bộ sạc báo; thiếu thì lấy điện áp × dòng sạc đo được.
  static double powerOf(BikeLogMsg t) {
    final chargerW = t.charging?.power ?? 0;
    if (chargerW > 0) return chargerW.toDouble();
    return t.voltage * (t.phase > 0 ? t.phase : 0.0);
  }

  final ChargeTracker tracker = ChargeTracker();
  Timer? _watchdog;
  int _rev = 0;
  int _savedCount = -1;

  @override
  ChargeState build() {
    ref.listen<BikeLogMsg?>(
      bleProvider.select((s) => s.lastTelemetry),
      (prev, next) => _onTelemetry(next),
    );
    ref.listen<BlePhase>(
      bleProvider.select((s) => s.phase),
      (prev, next) {
        if (next != BlePhase.connected) {
          tracker.onLinkLost();
          _publish();
        }
      },
    );
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _checkStale());
    ref.onDispose(() => _watchdog?.cancel());
    _restore();
    return const ChargeState();
  }

  void _onTelemetry(BikeLogMsg? t) {
    if (t == null) return;
    if (ref.read(bleProvider).phase != BlePhase.connected) return;
    final at = ref.read(bleProvider.notifier).lastTelemetryAt ?? DateTime.now();
    final charging = t.charging != null || t.phase > ChargeTracker.idleBandA;
    final currentA = t.phase > 0 ? t.phase : 0.0;
    final powerW = powerOf(t);
    tracker.onSample(
      at: at,
      charging: charging,
      powerW: powerW,
      voltage: t.voltage,
      currentA: currentA,
      soc: t.percent.toDouble(),
      tempC: t.bmsTemp > 0 ? t.bmsTemp : null,
    );
    _publish();
  }

  void _checkStale() {
    final last = tracker.lastSample;
    if (tracker.ongoing == null || last == null) return;
    if (DateTime.now().difference(last.at) > _staleAfter) {
      tracker.onLinkLost();
      _publish();
    }
  }

  void _publish() {
    state = ChargeState(
      revision: ++_rev,
      ongoing: tracker.ongoing,
      history: tracker.history,
      lastSampleAt: tracker.lastSample?.at,
    );
    if (tracker.history.length != _savedCount) _save();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        _savedCount = 0;
        return;
      }
      final list = jsonDecode(raw);
      if (list is! List) return;
      final parsed = <ChargeSession>[];
      for (final e in list) {
        final s = ChargeSession.fromJson(e);
        if (s != null) parsed.add(s);
      }
      // Gộp với phiên đã đóng trong lúc đang đọc (tránh mất phiên mới).
      final live = tracker.history;
      tracker.restore([...parsed, ...live.where((l) => !parsed.any((p) => p.start == l.start))]);
      _savedCount = tracker.history.length;
      _publish();
    } catch (_) {
      _savedCount = 0;
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = tracker.history.reversed.map((s) => s.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(data));
      _savedCount = tracker.history.length;
    } catch (_) {
      // Lưu lỗi không ảnh hưởng hiển thị; thử lại lần đóng phiên sau.
    }
  }

  Future<void> clearHistory() async {
    tracker.clearHistory();
    _publish();
    await _save();
  }
}

final chargeProvider =
    NotifierProvider<ChargeCenter, ChargeState>(ChargeCenter.new);
