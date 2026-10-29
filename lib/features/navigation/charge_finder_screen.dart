// Trạm sạc & Dẫn đường: GPS hiện tại, tìm trạm sạc (OSM), lập tuyến (OSRM),
// lập tuyến qua điểm sạc, chỉ dẫn rẽ dạng văn bản, ước tính pin đến nơi.
//
// Trung thực về dữ liệu:
//  • % pin chỉ dùng khi có khung telemetry MỚI (< 4s) và đang kết nối; nếu không,
//    KHÔNG ước tính pin đến nơi (không dùng số cũ như số trực tiếp).
//  • Mọi con số "đến nơi" là ước tính và ghi rõ cơ sở tính.
//  • Không xác minh trạm sạc tương thích với Datbike.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/services/charging_station_service.dart';
import '../../core/services/energy_estimator.dart';
import '../../core/services/map_tile_service.dart';
import '../../core/services/route_service.dart';
import '../../ui/app_theme.dart';

const double _kDetourFactor = 1.3; // đường thực tế ≈ 1.3 × đường chim bay (ước lượng)
const double _kReservePercent = 15;

class ChargeFinderScreen extends ConsumerStatefulWidget {
  const ChargeFinderScreen({super.key});

  @override
  ConsumerState<ChargeFinderScreen> createState() => _ChargeFinderScreenState();
}

class _ChargeFinderScreenState extends ConsumerState<ChargeFinderScreen> {
  static const Distance _dist = Distance();

  final MapController _map = MapController();
  StreamSubscription<Position>? _posSub;
  StreamSubscription<BikeTelemetry>? _bleSub;

  LatLng? _me;
  double? _heading;
  DateTime? _bikeAt;

  StationResult? _result;
  LatLng? _dest;
  ChargingStation? _target; // trạm đang dẫn đường tới
  ChargeStop? _stop; // trạm sạc chèn vào tuyến đích
  RouteResult? _route;
  int _stepIdx = 1;
  bool _loading = false;
  String? _error;
  String? _note;

  @override
  void initState() {
    super.initState();
    _bleSub = ref.read(bleProvider.notifier).telemetry.listen((t) {
      if (mounted) setState(() => _bikeAt = t.at);
    });
    _startLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }

  // ───────────── Vị trí ─────────────

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'GPS đang tắt trong hệ thống. Hãy bật vị trí rồi mở lại màn này.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _error = 'Chưa được cấp quyền vị trí nên không tìm được trạm sạc gần bạn.');
        return;
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(_onPosition, onError: (Object e) {
        if (mounted) setState(() => _error = 'Lỗi GPS: $e');
      });
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
      _onPosition(p, first: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không lấy được vị trí: $e');
    }
  }

  void _onPosition(Position p, {bool first = false}) {
    if (!mounted) return;
    final firstFix = _me == null;
    setState(() {
      _me = LatLng(p.latitude, p.longitude);
      _heading = p.heading >= 0 ? p.heading : _heading;
      _advanceStep();
    });
    if (firstFix || first) {
      _map.move(_me!, 14);
      if (_result == null) _loadStations();
    }
  }

  void _advanceStep() {
    final r = _route;
    final me = _me;
    if (r == null || me == null) return;
    while (_stepIdx < r.steps.length - 1 &&
        _dist.as(LengthUnit.Meter, me, r.steps[_stepIdx].location) < 30) {
      _stepIdx++;
    }
  }

  // ───────────── Pin ─────────────

  bool get _bleLive {
    final ble = ref.read(bleProvider);
    return ble.phase == BlePhase.connected &&
        _bikeAt != null &&
        DateTime.now().difference(_bikeAt!) < const Duration(seconds: 4);
  }

  int? get _livePercent => _bleLive ? ref.read(bleProvider).lastTelemetry?.percent : null;

  ConsumptionEstimate? get _consumption {
    final ble = ref.read(bleProvider);
    final live = _bleLive;
    return EnergyEstimator.estimate(
      history: [for (final t in ble.tripHistory) TripSample(t.distanceKm, t.usedPercent)],
      percent: live ? ble.lastTelemetry?.percent : null,
      kmLeft: live ? ble.lastTelemetry?.kmLeft : null,
    );
  }

  // ───────────── Tải dữ liệu / lập tuyến ─────────────

  Future<void> _loadStations() async {
    final me = _me;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ChargingStationService.fetchNear(me.latitude, me.longitude);
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
      _error = r.stations.isEmpty ? (r.error ?? 'Không có trạm sạc nào trong bán kính 8 km (theo dữ liệu OSM).') : null;
    });
  }

  Future<void> _routeToStation(ChargingStation s) async {
    final me = _me;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _note = null;
      _target = s;
      _dest = null;
      _stop = null;
    });
    try {
      final r = await RouteService.fetch([me, s.position]);
      if (!mounted) return;
      setState(() {
        _route = r;
        _stepIdx = 1;
      });
      _fit(r.points);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Chạm giữ trên bản đồ để chọn điểm đến → lập tuyến, tự chèn trạm sạc nếu pin không đủ.
  Future<void> _routeToDestination(LatLng dest) async {
    final me = _me;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _note = null;
      _dest = dest;
      _target = null;
      _stop = null;
    });
    try {
      var r = await RouteService.fetch([me, dest]);
      final pct = _livePercent;
      final cons = _consumption;
      String? note;
      ChargeStop? stop;
      if (pct == null || cons == null) {
        note = 'Không có dữ liệu pin trực tiếp từ xe nên không ước tính được pin đến nơi hay đề xuất trạm sạc.';
      } else if (ChargePlanner.needsCharging(
        startPercent: pct.toDouble(),
        totalKm: r.distanceKm,
        percentPerKm: cons.percentPerKm,
        reservePercent: _kReservePercent,
      )) {
        stop = ChargePlanner.pickStop(
          route: r.points,
          stations: _result?.stations ?? const [],
          startPercent: pct.toDouble(),
          percentPerKm: cons.percentPerKm,
          reservePercent: _kReservePercent,
        );
        if (stop != null) {
          r = await RouteService.fetch([me, stop.station.position, dest]);
          note = 'Pin ước tính không đủ tới đích (cơ sở: ${cons.basis}). Đã chèn trạm "${stop.station.name}" '
              '(~${stop.alongKm.toStringAsFixed(1)} km trên tuyến, pin tới trạm ước tính ${stop.batteryAtArrival.toStringAsFixed(0)}%).';
        } else {
          note = 'Pin ước tính không đủ tới đích và không có trạm nào gần tuyến mà vẫn tới được với pin ≥ ${_kReservePercent.toInt()}% '
              '(theo dữ liệu trạm đã tải). Hãy sạc trước khi đi hoặc chọn đích gần hơn.';
        }
      }
      if (!mounted) return;
      setState(() {
        _route = r;
        _stop = stop;
        _stepIdx = 1;
        _note = note;
      });
      _fit(r.points);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearRoute() => setState(() {
        _route = null;
        _dest = null;
        _target = null;
        _stop = null;
        _note = null;
        _error = null;
      });

  void _fit(List<LatLng> pts) {
    if (pts.length < 2) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(48),
    ));
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trạm sạc & Dẫn đường'),
        actions: [
          IconButton(
            tooltip: 'Tải lại trạm sạc',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadStations,
          ),
          if (_route != null)
            IconButton(tooltip: 'Xóa tuyến', icon: const Icon(Icons.clear_all_rounded), onPressed: _clearRoute),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 5, child: _mapView(me)),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          Expanded(flex: 5, child: _panel()),
        ],
      ),
    );
  }

  Widget _mapView(LatLng? me) {
    final stations = _result?.stations ?? const <ChargingStation>[];
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: me ?? const LatLng(16.0, 106.0),
        initialZoom: me == null ? 5 : 14,
        onLongPress: (_, p) => _routeToDestination(p),
      ),
      children: [
        MapTileService.buildTileLayer(style: MapTileStyle.fastCdn),
        if (_route != null)
          PolylineLayer(polylines: [
            Polyline(points: _route!.points, strokeWidth: 6, color: Colors.blue.withValues(alpha: 0.85)),
          ]),
        MarkerLayer(markers: [
          for (final s in stations)
            Marker(
              point: s.position,
              width: 36,
              height: 36,
              child: GestureDetector(
                onTap: () => _routeToStation(s),
                child: Icon(
                  Icons.ev_station_rounded,
                  size: 30,
                  color: (_stop?.station.id == s.id || _target?.id == s.id) ? Colors.orange : Colors.green.shade700,
                ),
              ),
            ),
          if (_dest != null)
            Marker(point: _dest!, width: 40, height: 40, child: const Icon(Icons.flag_rounded, color: Colors.red, size: 34)),
          if (me != null)
            Marker(
              point: me,
              width: 36,
              height: 36,
              child: Transform.rotate(
                angle: ((_heading ?? 0) * 3.1415926535 / 180),
                child: const Icon(Icons.navigation_rounded, color: Colors.blueAccent, size: 32),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _panel() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_error != null) _banner(_error!, AppColors.red),
        if (_route != null) ..._routePanel() else ..._stationPanel(),
      ],
    );
  }

  Widget _banner(String text, Color c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: AppColors.readable(c), fontSize: 13)),
      );

  List<Widget> _routePanel() {
    final r = _route!;
    final me = _me;
    // Quãng đường còn lại ≈ từ điểm gần nhất trên tuyến tới cuối tuyến.
    var remainingKm = r.distanceKm;
    if (me != null) {
      var bestI = 0;
      var bestD = double.infinity;
      for (var i = 0; i < r.points.length; i++) {
        final d = _dist.as(LengthUnit.Meter, me, r.points[i]);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      var m = 0.0;
      for (var i = bestI; i < r.points.length - 1; i++) {
        m += _dist.as(LengthUnit.Meter, r.points[i], r.points[i + 1]);
      }
      remainingKm = m / 1000.0;
    }
    final step = _stepIdx < r.steps.length ? r.steps[_stepIdx] : null;
    final toStepM = (step != null && me != null) ? _dist.as(LengthUnit.Meter, me, step.location) : null;

    final pct = _livePercent;
    final cons = _consumption;
    String battLine;
    if (pct == null) {
      battLine = 'Pin đến nơi: không có dữ liệu pin trực tiếp từ xe.';
    } else if (cons == null) {
      battLine = 'Pin hiện tại $pct% — chưa đủ dữ liệu để ước tính tiêu hao.';
    } else {
      final after = EnergyEstimator.batteryAfter(pct.toDouble(), remainingKm, cons.percentPerKm);
      battLine = 'Pin đến nơi (ước tính): ${after.clamp(-99, 100).toStringAsFixed(0)}%'
          '${after < 0 ? ' — KHÔNG ĐỦ' : ''}  ·  cơ sở: ${cons.basis}';
    }

    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.turn_right_rounded, size: 36),
          title: Text(step?.instruction ?? 'Đang theo tuyến', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          subtitle: Text(toStepM == null ? '' : 'sau ${toStepM >= 1000 ? '${(toStepM / 1000).toStringAsFixed(1)} km' : '${toStepM.round()} m'}'),
        ),
      ),
      const SizedBox(height: 6),
      Text('Còn ${remainingKm.toStringAsFixed(1)} km  ·  tổng tuyến ${r.distanceKm.toStringAsFixed(1)} km  ·  ~${(r.durationS / 60).round()} phút (theo ô tô, chỉ tham khảo)'),
      const SizedBox(height: 4),
      Text(battLine, style: TextStyle(color: (pct != null && cons != null && EnergyEstimator.batteryAfter(pct.toDouble(), remainingKm, cons.percentPerKm) < 0) ? AppColors.redText : null)),
      if (_note != null) ...[const SizedBox(height: 8), _banner(_note!, AppColors.amber)],
      const SizedBox(height: 8),
      _disclaimer(),
    ];
  }

  List<Widget> _stationPanel() {
    final res = _result;
    final me = _me;
    if (res == null) {
      return [const Padding(padding: EdgeInsets.all(16), child: Text('Đang chờ vị trí GPS để tìm trạm sạc…'))];
    }
    final cons = _consumption;
    final pct = _livePercent;
    final list = [...res.stations];
    if (me != null) {
      list.sort((a, b) => _dist.as(LengthUnit.Meter, me, a.position).compareTo(_dist.as(LengthUnit.Meter, me, b.position)));
    }
    return [
      _consumptionCard(pct, cons),
      if (res.fromCache)
        _banner('Không có mạng/máy chủ — đang hiện dữ liệu đã lưu lúc ${res.cachedAt?.toLocal().toString().substring(0, 16)}.', Colors.orange),
      Text('Chạm giữ trên bản đồ để chọn điểm đến và lập tuyến (tự chèn trạm sạc nếu pin không đủ).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const SizedBox(height: 6),
      for (final s in list.take(20))
        Builder(builder: (_) {
          final km = me == null ? null : _dist.as(LengthUnit.Kilometer, me, s.position);
          String sub = km == null ? '' : '~${km.toStringAsFixed(1)} km (đường chim bay)';
          if (km != null && pct != null && cons != null) {
            final b = EnergyEstimator.batteryAfter(pct.toDouble(), km * _kDetourFactor, cons.percentPerKm);
            sub += '  ·  pin tới nơi ước tính ${b.clamp(-99, 100).toStringAsFixed(0)}%';
          } else if (pct == null) {
            sub += '  ·  chưa có pin trực tiếp để ước tính';
          }
          if (s.sockets != null) sub += '\n${s.sockets}';
          return Card(
            child: ListTile(
              leading: Icon(Icons.ev_station_rounded, color: AppColors.tertiary),
              title: Text(s.name),
              subtitle: Text(sub),
              isThreeLine: s.sockets != null,
              trailing: const Icon(Icons.directions_rounded),
              onTap: () => _routeToStation(s),
            ),
          );
        }),
      if (list.isEmpty && !_loading) const Padding(padding: EdgeInsets.all(12), child: Text('Không có trạm sạc nào.')),
      const SizedBox(height: 8),
      _disclaimer(),
    ];
  }

  Widget _consumptionCard(int? pct, ConsumptionEstimate? cons) {
    String text;
    if (cons == null) {
      text = 'Tiêu hao: chưa đủ dữ liệu (cần vài chuyến ≥ 2 km đã lưu, hoặc xe đang kết nối và báo km còn lại).';
    } else {
      text = 'Tiêu hao ước tính: ${cons.percentPerKm.toStringAsFixed(2)} %/km (${cons.basis})';
      if (pct != null) {
        final range = EnergyEstimator.rangeKm(pct.toDouble(), _kReservePercent, cons.percentPerKm);
        text += '\nTầm đi ước tính tới mức dự phòng ${_kReservePercent.toInt()}%: ~${range.toStringAsFixed(0)} km (pin $pct%, số liệu trực tiếp)';
      } else {
        text += '\nKhông có % pin trực tiếp từ xe lúc này nên không tính tầm đi.';
      }
    }
    return Card(child: Padding(padding: const EdgeInsets.all(10), child: Text(text, style: const TextStyle(fontSize: 13))));
  }

  Widget _disclaimer() => Text(
        'Dữ liệu trạm sạc từ OpenStreetMap (cộng đồng nhập, có thể sai/thiếu); tuyến đường từ máy chủ OSRM demo (profile ô tô). '
        'App không xác minh trạm tương thích với bộ sạc Datbike. Không thao tác điện thoại khi đang lái.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
      );
}
