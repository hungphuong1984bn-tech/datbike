// Lưu/khôi phục các cấu hình App Dashboard (nhiều profile) bằng SharedPreferences.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_controller.dart';
import 'dashboard_model.dart';
import 'dashboard_sync.dart';

final dashboardStoreProvider = NotifierProvider<DashboardStore, DashStoreData>(
  DashboardStore.new,
);

/// Engine đồng bộ lên đồng hồ xe. Mặc định UNSUPPORTED (xem dashboard_sync.dart).
final dashboardSyncProvider = Provider<DashboardSyncEngine>((ref) {
  final e = DashboardSyncEngine();
  ref.onDispose(e.dispose);
  return e;
});

class DashboardStore extends Notifier<DashStoreData> {
  static const _key = 'dash_store_v1';

  @override
  DashStoreData build() {
    _load();
    return DashStoreData.seed();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = DashStoreData.decode(p.getString(_key));
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, state.encode());
    } catch (_) {}
  }

  void _set(DashStoreData d) {
    state = d;
    _save();
  }

  void setActive(String id) {
    if (!state.profiles.any((p) => p.id == id)) return;
    _set(DashStoreData(state.profiles, id));
  }

  /// Sửa cấu hình đang chọn (tự lưu).
  void updateActive(DashProfile Function(DashProfile) f) {
    final a = state.active;
    final n = f(a);
    _set(
      DashStoreData([
        for (final p in state.profiles) p.id == a.id ? n : p,
      ], a.id),
    );
  }

  /// Nhân bản cấu hình đang chọn thành cấu hình mới rồi chọn nó.
  void addFromActive(String name) {
    final a = state.active;
    final id = 'p${DateTime.now().microsecondsSinceEpoch}';
    final n = DashProfile(
      id: id,
      name: name.trim().isEmpty
          ? 'Cấu hình ${state.profiles.length + 1}'
          : name.trim(),
      theme: a.theme,
      layout: a.layout,
      accent: a.accent,
      widgets: List.of(a.widgets),
      alwaysOn: a.alwaysOn,
    );
    _set(DashStoreData([...state.profiles, n], id));
  }

  void rename(String name) {
    if (name.trim().isEmpty) return;
    updateActive((p) => p.copyWith(name: name.trim()));
  }

  /// Xóa cấu hình đang chọn; luôn giữ lại ít nhất một cấu hình.
  bool deleteActive() {
    if (state.profiles.length <= 1) return false;
    final id = state.activeId;
    final rest = state.profiles.where((p) => p.id != id).toList();
    _set(DashStoreData(rest, rest.first.id));
    return true;
  }
}

/// Dựng [DashInput] từ trạng thái BLE (hàm thuần → dễ kiểm thử).
DashInput buildDashInput({
  required BleState ble,
  required DateTime? lastTelemetryAt,
  required DateTime now,
  required int? regenLevel,
  double? gpsKmh,
  bool gpsLive = false,
}) {
  final connected = ble.phase == BlePhase.connected;
  final fresh =
      lastTelemetryAt != null &&
      now.difference(lastTelemetryAt) < const Duration(seconds: 4);
  final tripActive = ble.trip.duration > Duration.zero;
  return DashInput(
    bike: ble.lastTelemetry,
    bikeLive: connected && fresh,
    bleConnected: connected,
    gpsKmh: gpsKmh,
    gpsLive: gpsLive,
    regenLevel: regenLevel,
    tripKm: tripActive ? ble.trip.distanceKm : null,
    tripDuration: tripActive ? ble.trip.duration : null,
  );
}
