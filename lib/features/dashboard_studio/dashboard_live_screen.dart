// Đồng hồ phụ toàn màn hình (Always-On Dashboard) — chạy TRÊN ĐIỆN THOẠI.
// Đây KHÔNG phải đồng hồ nguyên bản của xe và không thay đổi màn hình xe.
//
// • Dữ liệu xe lấy từ telemetry đã có (không mở luồng BLE mới).
// • GPS chỉ chạy khi màn hình này mở; xin quyền khi cần; thiếu quyền → "--".
// • Giữ sáng màn hình nếu profile bật Always-On; cho phép xoay ngang khi mở.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/config/cluster_config.dart';
import '../../core/dashboard/dashboard_model.dart';
import '../../core/dashboard/dashboard_store.dart';
import '../../core/regen/regen_controller.dart';
import 'dashboard_view.dart';

class DashboardLiveScreen extends ConsumerStatefulWidget {
  const DashboardLiveScreen({super.key});

  @override
  ConsumerState<DashboardLiveScreen> createState() =>
      _DashboardLiveScreenState();
}

class _DashboardLiveScreenState extends ConsumerState<DashboardLiveScreen> {
  static const _channel = MethodChannel('vn.datbike/export');
  StreamSubscription<Position>? _gpsSub;
  Timer? _tick;
  double? _gpsKmh;
  DateTime? _gpsAt;
  String _gpsStatus = 'GPS: đang khởi động';
  late final bool _restorePortraitOnly;

  @override
  void initState() {
    super.initState();
    _restorePortraitOnly = !ref.read(clusterConfigProvider).allowRotate;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _startGps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keepAwake(ref.read(dashboardStoreProvider).active.alwaysOn);
      // Chỉ ĐỌC mức Regen hiện tại (không ghi).
      ref.read(regenProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _tick?.cancel();
    _keepAwake(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_restorePortraitOnly) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  Future<void> _keepAwake(bool on) async {
    try {
      await _channel.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted)
          setState(() => _gpsStatus = 'GPS: đang tắt trong hệ thống');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted)
          setState(() => _gpsStatus = 'GPS: chưa được cấp quyền vị trí');
        return;
      }
      _gpsSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              if (!mounted) return;
              setState(() {
                _gpsKmh = p.speed >= 0 ? p.speed * 3.6 : null;
                _gpsAt = DateTime.now();
                _gpsStatus = 'GPS: sai số ${p.accuracy.toStringAsFixed(0)} m';
              });
            },
            onError: (Object e) {
              if (mounted) setState(() => _gpsStatus = 'GPS: lỗi — $e');
            },
          );
    } catch (e) {
      if (mounted) setState(() => _gpsStatus = 'GPS: lỗi — $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dashboardStoreProvider);
    final profile = store.active;
    final ble = ref.watch(bleProvider);
    final regen = ref.watch(regenProvider);
    final now = DateTime.now();
    final gpsLive =
        _gpsAt != null && now.difference(_gpsAt!) < const Duration(seconds: 5);
    final input = buildDashInput(
      ble: ble,
      lastTelemetryAt: ref.read(bleProvider.notifier).lastTelemetryAt,
      now: now,
      regenLevel: regen.currentIndex,
      gpsKmh: _gpsKmh,
      gpsLive: gpsLive,
    );
    final values = resolveDash(input);
    final skin = skinFor(profile.theme, accentOverride: profile.accent);

    final conn = input.bikeLive
        ? 'XE: TRỰC TIẾP'
        : (ble.phase == BlePhase.connected
              ? 'XE: CHƯA CÓ DỮ LIỆU MỚI'
              : 'XE: MẤT KẾT NỐI');
    final connColor = input.bikeLive
        ? skin.ok
        : (ble.phase == BlePhase.connected ? skin.warn : skin.bad);

    return Scaffold(
      backgroundColor: skin.bg1,
      body: Stack(
        children: [
          Positioned.fill(
            child: DashboardView(profile: profile, values: values),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: skin.bg1.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('dash_close'),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Đóng',
                        icon: Icon(Icons.close_rounded, color: skin.fg),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Text(
                        conn,
                        style: TextStyle(
                          color: connColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        gpsLive ? 'GPS: OK' : _gpsStatus,
                        style: TextStyle(color: skin.dim, fontSize: 11),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'ĐỒNG HỒ PHỤ TRÊN ĐIỆN THOẠI',
                        style: TextStyle(
                          color: skin.dim,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
