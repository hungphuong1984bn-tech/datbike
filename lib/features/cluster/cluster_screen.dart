// Đồng hồ lái xe (Cluster) — chỉ HIỂN THỊ, không có nút điều khiển xe để
// tránh bấm nhầm khi đang chạy. Portrait cố định (xoay chỉ khi người dùng bật).
//
// Quy tắc dữ liệu:
//  • Giá trị BLE chỉ coi là "trực tiếp" khi đang kết nối VÀ khung tin mới < 4s.
//    Ngược lại hiển thị mờ + nhãn "DỮ LIỆU CŨ", không giả làm số trực tiếp.
//  • Tốc độ XE (BLE) và tốc độ GPS (điện thoại) luôn được phân biệt rõ.
//  • "Ước tính" (quãng đường còn lại, công suất tính V×A) có nhãn riêng.

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/config/cluster_config.dart';
import '../../core/proto/bike_log.dart';
import '../dashboard/widgets/cockpit_live_map.dart';

const Duration kBleFreshWindow = Duration(seconds: 4);
const Duration kGpsFreshWindow = Duration(seconds: 5);

String formatClusterDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Chọn tốc độ hiển thị. Trả về (giá trị, nhãn nguồn). Giá trị null = không có
/// dữ liệu hợp lệ. Hàm thuần để dễ kiểm thử.
({double? value, String label}) pickSpeed({
  required SpeedSource preferred,
  required double? bleKmh,
  required double? gpsKmh,
}) {
  final primary = preferred == SpeedSource.ble ? bleKmh : gpsKmh;
  final secondary = preferred == SpeedSource.ble ? gpsKmh : bleKmh;
  final pName = preferred == SpeedSource.ble ? 'XE (BLE)' : 'GPS';
  final sName = preferred == SpeedSource.ble ? 'GPS' : 'XE (BLE)';
  if (primary != null) return (value: primary, label: pName);
  if (secondary != null) return (value: secondary, label: '$sName · dự phòng');
  return (value: null, label: pName);
}

class _Palette {
  final Color bg, card, text, dim, accent, ok, warn, bad;
  const _Palette(this.bg, this.card, this.text, this.dim, this.accent, this.ok, this.warn, this.bad);
}

_Palette _paletteFor(ClusterConfig c, bool night) {
  Color baseBg;
  Color accent;
  switch (c.theme) {
    case ClusterTheme.sport:
      baseBg = night ? const Color(0xFF000000) : const Color(0xFF14141A);
      accent = const Color(0xFFFF4D2E);
    case ClusterTheme.minimal:
      baseBg = night ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
      accent = night ? const Color(0xFFE5E7EB) : const Color(0xFF111827);
    case ClusterTheme.touring:
      baseBg = night ? const Color(0xFF07131F) : const Color(0xFFEAF2F8);
      accent = const Color(0xFF14B8A6);
    case ClusterTheme.original:
      baseBg = night ? const Color(0xFF0B0F17) : const Color(0xFFF8F9FA);
      accent = const Color(0xFF2563EB);
  }
  final bg = c.background != null ? Color(c.background!) : baseBg;
  final acc = c.accent != null ? Color(c.accent!) : accent;
  final lightBg = bg.computeLuminance() > 0.5;
  return _Palette(
    bg,
    lightBg ? const Color(0xFFFFFFFF) : Color.alphaBlend(const Color(0x14FFFFFF), bg),
    lightBg ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    lightBg ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
    acc,
    const Color(0xFF22C55E),
    const Color(0xFFF59E0B),
    const Color(0xFFEF4444),
  );
}

class ClusterScreen extends ConsumerStatefulWidget {
  const ClusterScreen({super.key});

  @override
  ConsumerState<ClusterScreen> createState() => _ClusterScreenState();
}

class _ClusterScreenState extends ConsumerState<ClusterScreen> {
  static const _channel = MethodChannel('vn.mybike/export');

  StreamSubscription<BikeTelemetry>? _bleSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _tick;

  BikeLogMsg? _bike;
  DateTime? _bikeAt;

  double? _gpsKmh;
  DateTime? _gpsAt;
  String _gpsStatus = 'GPS: đang khởi động';

  @override
  void initState() {
    super.initState();
    _bleSub = ref.read(bleProvider.notifier).telemetry.listen((t) {
      if (!mounted) return;
      setState(() {
        _bike = t.bike;
        _bikeAt = t.at;
      });
    });
    // Tick 1s: cập nhật độ "cũ" của dữ liệu và chế độ ngày/đêm tự động.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _startGps();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applySystem(ref.read(clusterConfigProvider)));
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _gpsSub?.cancel();
    _tick?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _setKeepAwake(false);
    super.dispose();
  }

  Future<void> _setKeepAwake(bool on) async {
    try {
      await _channel.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {
      // Nền tảng không hỗ trợ (vd. web preview) — bỏ qua.
    }
  }

  void _applySystem(ClusterConfig c) {
    SystemChrome.setEnabledSystemUIMode(
      c.fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _setKeepAwake(c.keepAwake);
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _gpsStatus = 'GPS: đang tắt trong hệ thống');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsStatus = 'GPS: chưa được cấp quyền vị trí');
        return;
      }
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
      ).listen(
        (p) {
          if (!mounted) return;
          setState(() {
            // pos.speed < 0 nghĩa là không có giá trị.
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

  bool _isNight(ClusterConfig c) => switch (c.nightMode) {
        NightMode.day => false,
        NightMode.night => true,
        NightMode.auto => DateTime.now().hour >= 18 || DateTime.now().hour < 6,
      };

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(clusterConfigProvider);
    ref.listen<ClusterConfig>(clusterConfigProvider, (prev, next) {
      if (prev == null || prev.fullscreen != next.fullscreen || prev.keepAwake != next.keepAwake) {
        _applySystem(next);
      }
    });
    final ble = ref.watch(bleProvider);
    final pal = _paletteFor(cfg, _isNight(cfg));
    final now = DateTime.now();

    final msg = _bike ?? ble.lastTelemetry;
    final bleAge = _bikeAt == null ? null : now.difference(_bikeAt!);
    final bleLive = ble.phase == BlePhase.connected && bleAge != null && bleAge < kBleFreshWindow;
    final gpsLive = _gpsAt != null && now.difference(_gpsAt!) < kGpsFreshWindow;

    final speed = pickSpeed(
      preferred: cfg.speedSource,
      bleKmh: (bleLive && msg != null) ? msg.speed : null,
      gpsKmh: gpsLive ? _gpsKmh : null,
    );

    final scale = cfg.fontScale;
    final top = _topBar(pal, cfg, ble, bleLive, bleAge, gpsLive);

    Widget upper = _upper(cfg, pal, ble, msg, bleLive, bleAge, speed, scale);

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(
          children: [
            top,
            if (!bleLive) _staleBanner(pal, ble, bleAge),
            if (cfg.showMap) ...[
              Expanded(flex: 5, child: SingleChildScrollView(child: upper)),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CockpitLiveMap(currentSpeedKmh: speed.value ?? 0),
                  ),
                ),
              ),
            ] else
              Expanded(child: SingleChildScrollView(child: upper)),
          ],
        ),
      ),
    );
  }

  Widget _topBar(_Palette pal, ClusterConfig cfg, BleState ble, bool bleLive, Duration? age, bool gpsLive) {
    final connText = switch (ble.phase) {
      BlePhase.connected => bleLive ? 'XE: TRỰC TIẾP' : 'XE: CHƯA CÓ DỮ LIỆU MỚI',
      BlePhase.connecting => 'XE: ĐANG KẾT NỐI',
      BlePhase.reconnecting => 'XE: ĐANG KẾT NỐI LẠI',
      BlePhase.scanning => 'XE: ĐANG QUÉT',
      _ => 'XE: MẤT KẾT NỐI',
    };
    final connColor = bleLive ? pal.ok : (ble.phase == BlePhase.reconnecting || ble.phase == BlePhase.connecting ? pal.warn : pal.bad);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            iconSize: 28,
            color: pal.dim,
            tooltip: 'Đóng đồng hồ',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connText, style: TextStyle(color: connColor, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                Text(_gpsStatus, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: gpsLive ? pal.dim : pal.warn, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            iconSize: 28,
            color: pal.dim,
            tooltip: 'Tùy chỉnh đồng hồ',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const _ClusterSettingsSheet(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staleBanner(_Palette pal, BleState ble, Duration? age) {
    final txt = age == null
        ? 'Chưa nhận dữ liệu từ xe — số liệu xe hiển thị "--"'
        : 'DỮ LIỆU CŨ (${age.inSeconds}s trước) — không phải số liệu trực tiếp';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: pal.warn.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
      child: Text(txt, style: TextStyle(color: pal.warn, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _upper(ClusterConfig cfg, _Palette pal, BleState ble, BikeLogMsg? m, bool live, Duration? age,
      ({double? value, String label}) speed, double scale) {
    final visible = cfg.visible;
    final tiles = visible.where((e) => e != ClusterMetric.speed).toList();
    final theme = cfg.theme;
    final compact = cfg.showMap;
    final heroSize = (switch (theme) {
          ClusterTheme.sport => 150.0,
          ClusterTheme.minimal => 130.0,
          ClusterTheme.touring => 104.0,
          ClusterTheme.original => 110.0,
        }) *
        scale *
        (compact ? 0.6 : 1.0);
    final heroWeight = switch (theme) {
      ClusterTheme.sport => FontWeight.w900,
      ClusterTheme.minimal => FontWeight.w200,
      ClusterTheme.touring => FontWeight.w600,
      ClusterTheme.original => FontWeight.w700,
    };
    final columns = compact ? 3 : 2;
    final cardStyle = theme == ClusterTheme.minimal ? _CardKind.plain : (theme == ClusterTheme.sport ? _CardKind.filled : _CardKind.outlined);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        children: [
          if (visible.contains(ClusterMetric.speed)) _hero(cfg, pal, speed, heroSize, heroWeight, m, live),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: compact ? 1.25 : 1.55,
            children: [for (final t in tiles) _tile(t, cfg, pal, ble, m, live, age, scale, cardStyle)],
          ),
        ],
      ),
    );
  }

  Widget _hero(ClusterConfig cfg, _Palette pal, ({double? value, String label}) speed, double size, FontWeight w,
      BikeLogMsg? m, bool bleLive) {
    final v = speed.value;
    final now = DateTime.now();
    final gpsLive = _gpsAt != null && now.difference(_gpsAt!) < kGpsFreshWindow;
    final bleTxt = (bleLive && m != null) ? m.speed.toStringAsFixed(0) : '--';
    final gpsTxt = (gpsLive && _gpsKmh != null) ? _gpsKmh!.toStringAsFixed(0) : '--';
    final speedText = Text(
      v == null ? '--' : v.toStringAsFixed(0),
      style: TextStyle(
        fontSize: size,
        height: 1.0,
        fontWeight: w,
        color: v == null ? pal.dim : pal.accent,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final core = cfg.theme == ClusterTheme.original
        ? SizedBox(
            width: size * 1.9,
            height: size * 1.9,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: ((v ?? 0) / 100).clamp(0.0, 1.0),
                  strokeWidth: 10,
                  backgroundColor: pal.card,
                  color: pal.accent,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [speedText, Text('km/h', style: TextStyle(color: pal.dim, fontSize: 16 * cfg.fontScale))]),
            ]),
          )
        : Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(fit: BoxFit.scaleDown, child: speedText),
            Text('km/h', style: TextStyle(color: pal.dim, fontSize: 18 * cfg.fontScale, fontWeight: FontWeight.w600)),
          ]);
    return Column(children: [
      core,
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20)),
        child: Text(
          'NGUỒN: ${speed.label}   ·   XE $bleTxt   GPS $gpsTxt',
          style: TextStyle(color: pal.dim, fontSize: 12 * cfg.fontScale, fontWeight: FontWeight.w700),
        ),
      ),
    ]);
  }

  Widget _tile(ClusterMetric t, ClusterConfig cfg, _Palette pal, BleState ble, BikeLogMsg? m, bool live,
      Duration? age, double scale, _CardKind kind) {
    String value = '--';
    String unit = '';
    String? sub;
    double? progress;
    Color color = pal.text;

    final have = m != null;
    switch (t) {
      case ClusterMetric.battery:
        if (have) {
          value = '${m.percent}';
          unit = '%';
          progress = (m.percent / 100).clamp(0.0, 1.0);
          color = m.percent <= 15 ? pal.bad : (m.percent <= 30 ? pal.warn : pal.text);
          sub = m.kmLeft > 0 ? 'còn ~${m.kmLeft.toStringAsFixed(0)} km (xe ước tính)' : null;
        }
      case ClusterMetric.odo:
        if (have) {
          value = m.odo.toStringAsFixed(1);
          unit = 'km';
        }
      case ClusterMetric.voltage:
        if (have) {
          value = m.voltage.toStringAsFixed(1);
          unit = 'V';
        }
      case ClusterMetric.current:
        if (have) {
          value = m.phase.toStringAsFixed(1);
          unit = 'A';
          sub = 'dòng pha động cơ';
        }
      case ClusterMetric.power:
        if (have && m.voltage > 0) {
          value = (m.voltage * m.phase / 1000.0).toStringAsFixed(2);
          unit = 'kW';
          sub = 'tính từ V×A (ước tính)';
        }
      case ClusterMetric.tripDistance:
        value = ble.trip.distanceKm.toStringAsFixed(1);
        unit = 'km';
        sub = 'chuyến hiện tại';
      case ClusterMetric.tripTime:
        value = formatClusterDuration(ble.trip.duration);
        sub = 'chuyến hiện tại';
      case ClusterMetric.connection:
        value = switch (ble.phase) {
          BlePhase.connected => live ? 'Tốt' : 'Chờ dữ liệu',
          BlePhase.reconnecting => 'Kết nối lại #${ble.reconnectAttempt}',
          BlePhase.connecting => 'Đang kết nối',
          BlePhase.scanning => 'Đang quét',
          _ => 'Mất kết nối',
        };
        sub = ble.rssi != null ? 'RSSI ${ble.rssi} dBm' : null;
        color = live ? pal.ok : pal.warn;
      case ClusterMetric.speed:
        break;
    }

    // Số liệu xe (không phải ô kết nối / chuyến đi tính cục bộ) bị mờ khi không trực tiếp.
    final isBikeData = t == ClusterMetric.battery ||
        t == ClusterMetric.odo ||
        t == ClusterMetric.voltage ||
        t == ClusterMetric.current ||
        t == ClusterMetric.power;
    final stale = isBikeData && !live;
    final shownColor = stale ? pal.dim : color;

    final decoration = switch (kind) {
      _CardKind.filled => BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(14)),
      _CardKind.outlined => BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.dim.withValues(alpha: 0.25)),
        ),
      _CardKind.plain => BoxDecoration(border: Border(bottom: BorderSide(color: pal.dim.withValues(alpha: 0.2)))),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            stale ? '${t.label.toUpperCase()} · CŨ' : t.label.toUpperCase(),
            style: TextStyle(color: pal.dim, fontSize: 11 * scale, fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: shownColor,
                      fontSize: 30 * scale,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(color: pal.dim, fontSize: 13 * scale)),
              ],
            ],
          ),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: pal.dim.withValues(alpha: 0.25),
                color: stale ? pal.dim : shownColor == pal.text ? pal.accent : shownColor,
              ),
            )
          else if (sub != null)
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.dim, fontSize: 10.5 * scale)),
        ],
      ),
    );
  }
}

enum _CardKind { filled, outlined, plain }

// ───────────────────────── Cài đặt đồng hồ ─────────────────────────

class _ClusterSettingsSheet extends ConsumerWidget {
  const _ClusterSettingsSheet();

  static const _accents = <int?>[null, 0xFFFF4D2E, 0xFFF59E0B, 0xFF22C55E, 0xFF14B8A6, 0xFF2563EB, 0xFFA855F7, 0xFFFFFFFF];
  static const _backgrounds = <int?>[null, 0xFF000000, 0xFF0B0F17, 0xFF1F2937, 0xFFFFFFFF];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(clusterConfigProvider);
    final ctl = ref.read(clusterConfigProvider.notifier);
    final h = MediaQuery.of(context).size.height * 0.85;

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.6)),
        );

    Widget swatch(int? color, int? selected, VoidCallback onTap, {required Color fallback}) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: color == null ? fallback : Color(color),
              shape: BoxShape.circle,
              border: Border.all(width: selected == color ? 3 : 1, color: selected == color ? Colors.blue : Colors.grey),
            ),
            child: color == null ? const Icon(Icons.auto_awesome, size: 16, color: Colors.white70) : null,
          ),
        );

    return SizedBox(
      height: h,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          section('GIAO DIỆN'),
          SegmentedButton<ClusterTheme>(
            segments: [for (final t in ClusterTheme.values) ButtonSegment(value: t, label: Text(t.label))],
            selected: {cfg.theme},
            onSelectionChanged: (s) => ctl.setTheme(s.first),
          ),
          section('NGÀY / ĐÊM'),
          SegmentedButton<NightMode>(
            segments: const [
              ButtonSegment(value: NightMode.auto, label: Text('Tự động')),
              ButtonSegment(value: NightMode.day, label: Text('Ngày')),
              ButtonSegment(value: NightMode.night, label: Text('Đêm')),
            ],
            selected: {cfg.nightMode},
            onSelectionChanged: (s) => ctl.update(cfg.copyWith(nightMode: s.first)),
          ),
          section('NGUỒN TỐC ĐỘ CHÍNH'),
          SegmentedButton<SpeedSource>(
            segments: const [
              ButtonSegment(value: SpeedSource.ble, label: Text('Xe (BLE)')),
              ButtonSegment(value: SpeedSource.gps, label: Text('GPS')),
            ],
            selected: {cfg.speedSource},
            onSelectionChanged: (s) => ctl.update(cfg.copyWith(speedSource: s.first)),
          ),
          section('MÀU NHẤN'),
          Row(children: [
            for (final c in _accents) swatch(c, cfg.accent, () => ctl.update(c == null ? cfg.copyWith(clearAccent: true) : cfg.copyWith(accent: c)), fallback: Colors.blueGrey),
          ]),
          section('MÀU NỀN'),
          Row(children: [
            for (final c in _backgrounds) swatch(c, cfg.background, () => ctl.update(c == null ? cfg.copyWith(clearBackground: true) : cfg.copyWith(background: c)), fallback: Colors.blueGrey),
          ]),
          section('CỠ CHỮ  (${(cfg.fontScale * 100).round()}%)'),
          Slider(
            min: 0.8,
            max: 1.4,
            divisions: 12,
            value: cfg.fontScale,
            onChanged: (v) => ctl.update(cfg.copyWith(fontScale: v)),
          ),
          section('HIỂN THỊ'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kết hợp bản đồ'),
            subtitle: const Text('Bản đồ ở nửa dưới màn hình'),
            value: cfg.showMap,
            onChanged: (v) => ctl.update(cfg.copyWith(showMap: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Giữ màn hình sáng'),
            value: cfg.keepAwake,
            onChanged: (v) => ctl.update(cfg.copyWith(keepAwake: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Toàn màn hình'),
            value: cfg.fullscreen,
            onChanged: (v) => ctl.update(cfg.copyWith(fullscreen: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cho phép xoay ngang'),
            subtitle: const Text('Mặc định TẮT: đồng hồ luôn ở chiều dọc'),
            value: cfg.allowRotate,
            onChanged: (v) => ctl.update(cfg.copyWith(allowRotate: v)),
          ),
          section('Ô DỮ LIỆU — bật/tắt và kéo để sắp xếp'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: ctl.reorder,
            children: [
              for (var i = 0; i < cfg.order.length; i++)
                SwitchListTile(
                  key: ValueKey(cfg.order[i]),
                  contentPadding: EdgeInsets.zero,
                  title: Text(cfg.order[i].label),
                  secondary: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                  value: !cfg.hidden.contains(cfg.order[i]),
                  onChanged: (v) => ctl.toggleMetric(cfg.order[i], v),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Khôi phục mặc định'),
            onPressed: () => ctl.resetToDefaults(),
          ),
        ],
      ),
    );
  }
}
