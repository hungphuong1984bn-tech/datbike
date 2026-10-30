// TRUNG TÂM TÌM KIẾM TRẠM SẠC — bản đồ toàn màn hình + thẻ trạm, tìm kiếm,
// bộ lọc, chi tiết, yêu thích, báo cáo, chỉ đường (app + ứng dụng bản đồ ngoài).
//
// Trung thực về dữ liệu:
//  • Trạm chỉ hiện thuộc tính mà nguồn dữ liệu CÓ; thiếu → "Chưa có dữ liệu".
//  • Loại xe chỉ lấy từ thẻ nguồn; trạm không rõ loại xe KHÔNG được coi là dùng được.
//  • % pin chỉ dùng khi có khung telemetry MỚI (< 4 s) và đang kết nối.
//  • Mọi con số "tới nơi" là ước tính, kèm cơ sở tính; không khẳng định chắc chắn.
//  • Không giả lập dẫn đường thời gian thực: chỉ có tuyến + chỉ dẫn văn bản theo
//    GPS điện thoại; dẫn đường đầy đủ giao cho ứng dụng bản đồ ngoài.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/charging/external_nav.dart';
import '../../core/charging/place_search_service.dart';
import '../../core/charging/station_search.dart';
import '../../core/charging/station_user_store.dart';
import '../../core/services/charging_station_service.dart';
import '../../core/services/energy_estimator.dart';
import '../../core/services/map_tile_service.dart';
import '../../core/services/route_service.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import 'station_detail_screen.dart';
import 'station_widgets.dart';

const double _kCardW = 292;
const double _kCardGap = 10;

class ChargeFinderScreen extends ConsumerStatefulWidget {
  const ChargeFinderScreen({super.key});

  @override
  ConsumerState<ChargeFinderScreen> createState() => _ChargeFinderScreenState();
}

class _ChargeFinderScreenState extends ConsumerState<ChargeFinderScreen> {
  static const Distance _dist = Distance();
  static const List<double?> _radii = [5, 10, 20, 50, null];

  final MapController _map = MapController();
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _cards = ScrollController();
  StreamSubscription<Position>? _posSub;
  StreamSubscription<BikeTelemetry>? _bleSub;
  Timer? _tick;

  // Vị trí
  LatLng? _me;
  double? _heading;
  bool _permDenied = false;
  String? _locError;
  DateTime? _bikeAt;

  // Dữ liệu trạm
  StationResult? _result;
  double _loadedRadiusKm = 0;
  LatLng? _center; // tâm tìm kiếm do người dùng chọn (null = quanh vị trí hiện tại)
  String? _centerName;
  StationFilter _filter = const StationFilter();
  List<StationHit> _hits = const [];
  ChargingStation? _selected;
  Set<String> _favIds = {};
  bool _listMode = false;
  bool _loading = false;
  String? _error;

  // Tìm địa điểm
  List<PlaceHit> _places = const [];
  List<String> _history = const [];
  bool _searchingPlace = false;
  String? _placeError;

  // Tuyến trong app
  LatLng? _dest;
  ChargingStation? _target;
  ChargeStop? _stop;
  RouteResult? _route;
  int _stepIdx = 1;
  String? _note;

  LatLng? get _origin => _center ?? _me;

  @override
  void initState() {
    super.initState();
    _bleSub = ref.read(bleProvider.notifier).telemetry.listen((t) {
      if (mounted) setState(() => _bikeAt = t.at);
    });
    // Làm mới nhãn "dữ liệu pin còn mới" khi telemetry ngừng về.
    _tick = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _loadLocal();
    _startLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _bleSub?.cancel();
    _tick?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _cards.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final fav = await StationUserStore.favorites();
    final hist = await StationUserStore.history();
    if (!mounted) return;
    setState(() {
      _favIds = {for (final s in fav) s.id};
      _history = hist;
    });
  }

  // ───────────── Vị trí ─────────────

  Future<void> _startLocation() async {
    _posSub?.cancel();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() {
            _permDenied = false;
            _locError = 'GPS đang tắt trong hệ thống. Bật vị trí để tìm trạm gần bạn, hoặc dùng ô tìm kiếm.';
          });
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _permDenied = true;
            _locError = 'Chưa được cấp quyền vị trí nên không tự tìm được trạm gần bạn. '
                'Bạn vẫn có thể tìm theo tên, địa chỉ, tỉnh/thành.';
          });
        }
        return;
      }
      if (mounted) setState(() {
            _permDenied = false;
            _locError = null;
          });
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(_onPosition, onError: (Object e) {
        if (mounted) setState(() => _locError = 'Lỗi GPS: $e');
      });
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
      _onPosition(p);
    } catch (e) {
      if (mounted) setState(() => _locError = 'Không lấy được vị trí: $e');
    }
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    final firstFix = _me == null;
    setState(() {
      _me = LatLng(p.latitude, p.longitude);
      _heading = p.heading >= 0 ? p.heading : _heading;
      _advanceStep();
      if (!firstFix) _recompute();
    });
    if (firstFix) {
      if (_center == null) {
        _safeMove(_me!, 14);
        _loadStations();
      }
    }
  }

  void _advanceStep() {
    final r = _route;
    final me = _me;
    if (r == null || me == null) return;
    while (_stepIdx < r.steps.length - 1 && _dist.as(LengthUnit.Meter, me, r.steps[_stepIdx].location) < 30) {
      _stepIdx++;
    }
  }

  void _safeMove(LatLng p, double zoom) {
    try {
      _map.move(p, zoom);
    } catch (_) {
      // Bản đồ chưa dựng xong — bỏ qua, lần định vị sau sẽ di chuyển.
    }
  }

  // ───────────── Pin (chỉ dữ liệu trực tiếp) ─────────────

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

  // ───────────── Tải & lọc trạm ─────────────

  void _recompute() {
    _hits = StationSearch.apply(_result?.stations ?? const [], _filter, origin: _origin);
  }

  Future<void> _loadStations() async {
    final o = _origin;
    if (o == null) return;
    final km = _filter.radiusKm ?? 50;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ChargingStationService.fetchNear(o.latitude, o.longitude, radiusM: (km * 1000).round());
    if (!mounted) return;
    setState(() {
      _result = r;
      _loadedRadiusKm = km;
      _loading = false;
      _recompute();
      _error = r.stations.isEmpty ? (r.error ?? 'Nguồn dữ liệu không có trạm sạc nào trong bán kính ${km.toStringAsFixed(0)} km.') : null;
    });
  }

  void _setRadius(double? km) {
    setState(() {
      _filter = _filter.copyWith(radiusKm: km);
      _recompute();
    });
    // Mở rộng bán kính vượt vùng đã tải → tải lại.
    if ((km ?? 50) > _loadedRadiusKm) _loadStations();
  }

  void _select(ChargingStation s, {bool scrollCard = true}) {
    setState(() => _selected = s);
    _safeMove(s.position, math.max(_cameraZoom, 15));
    if (scrollCard) {
      final i = _hits.indexWhere((h) => h.station.id == s.id);
      if (i >= 0 && _cards.hasClients) {
        _cards.animateTo(
          (i * (_kCardW + _kCardGap)).clamp(0, _cards.position.maxScrollExtent).toDouble(),
          duration: AppMotion.slow,
          curve: AppMotion.curve,
        );
      }
    }
  }

  double get _cameraZoom {
    try {
      return _map.camera.zoom;
    } catch (_) {
      return 14;
    }
  }

  // ───────────── Tìm kiếm địa điểm ─────────────

  Future<void> _submitSearch(String text) async {
    final q = text.trim();
    _searchFocus.unfocus();
    if (q.isEmpty) {
      setState(() {
        _filter = _filter.copyWith(query: '');
        _places = const [];
        _recompute();
      });
      return;
    }
    await StationUserStore.addHistory(q);
    _history = await StationUserStore.history();
    setState(() {
      _filter = _filter.copyWith(query: q);
      _searchingPlace = true;
      _placeError = null;
      _places = const [];
      _recompute();
    });
    try {
      final hits = await PlaceSearchService.search(q);
      if (mounted) setState(() => _places = hits);
    } catch (e) {
      if (mounted) setState(() => _placeError = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _searchingPlace = false);
    }
  }

  void _pickPlace(PlaceHit p) {
    setState(() {
      _center = p.position;
      _centerName = p.name.split(',').first;
      _filter = _filter.copyWith(query: '');
      _places = const [];
      _result = null;
      _selected = null;
    });
    _searchCtl.clear();
    _safeMove(p.position, 13);
    _loadStations();
  }

  void _clearSearch() {
    _searchCtl.clear();
    setState(() {
      _filter = _filter.copyWith(query: '');
      _places = const [];
      _placeError = null;
      if (_center != null) {
        _center = null;
        _centerName = null;
        _result = null;
      }
      _recompute();
    });
    if (_result == null && _me != null) {
      _safeMove(_me!, 14);
      _loadStations();
    }
  }

  void _recenter() {
    final me = _me;
    if (me == null) {
      _startLocation();
      return;
    }
    if (_center != null) {
      _clearSearch();
    } else {
      _safeMove(me, 15);
    }
  }

  // ───────────── Tuyến trong app ─────────────

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
        reservePercent: kReservePercent,
      )) {
        // Chỉ đề xuất trạm dùng được cho xe máy (không rõ / ô tô thì không).
        final usable = [
          for (final s in _result?.stations ?? const <ChargingStation>[])
            if (s.supportsMotorbike && s.status != StationStatus.closed) s,
        ];
        stop = ChargePlanner.pickStop(
          route: r.points,
          stations: usable,
          startPercent: pct.toDouble(),
          percentPerKm: cons.percentPerKm,
          reservePercent: kReservePercent,
        );
        if (stop != null) {
          r = await RouteService.fetch([me, stop.station.position, dest]);
          note = 'Pin ước tính không đủ tới đích (cơ sở: ${cons.basis}). Đã chèn trạm "${stop.station.name}" '
              '(~${stop.alongKm.toStringAsFixed(1)} km trên tuyến, pin tới trạm ước tính ${stop.batteryAtArrival.toStringAsFixed(0)}%).';
        } else {
          note = 'Pin ước tính không đủ tới đích và không có trạm xác định hỗ trợ xe máy gần tuyến mà vẫn tới được '
              'với pin ≥ ${kReservePercent.toInt()}% (theo dữ liệu đã tải). Hãy sạc trước khi đi hoặc chọn đích gần hơn.';
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
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(48, 150, 48, 220),
      ));
    } catch (_) {}
  }

  // ───────────── Hành động ─────────────

  Future<void> _openDetail(ChargingStation s) async {
    final res = await Navigator.of(context).push<StationDetailResult>(
      MaterialPageRoute(
        builder: (_) => StationDetailScreen(
          station: s,
          me: _me,
          livePercent: _livePercent,
          consumption: _consumption,
        ),
      ),
    );
    await _loadLocal();
    if (res == StationDetailResult.routeInApp && mounted) {
      setState(() => _listMode = false);
      _routeToStation(s);
    }
  }

  Future<void> _toggleFav(ChargingStation s) async {
    await StationUserStore.toggleFavorite(s);
    await _loadLocal();
  }

  Future<void> _openSaved() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const _SavedSheet(),
    );
    if (!mounted) return;
    if (picked is ChargingStation) {
      // Trạm đã lưu có thể nằm ngoài vùng đang tải: thêm tạm vào danh sách để chọn được (kể cả khi offline).
      final cur = _result?.stations ?? const <ChargingStation>[];
      if (!cur.any((e) => e.id == picked.id)) {
        setState(() {
          _result = StationResult([...cur, picked], fromCache: _result?.fromCache ?? false, cachedAt: _result?.cachedAt, error: _result?.error);
          _filter = _filter.copyWith(radiusKm: null);
          _recompute();
        });
      }
      _select(picked);
      _openDetail(picked);
    } else if (picked is String) {
      _searchCtl.text = picked;
      _submitSearch(picked);
    }
  }

  Future<void> _openFilters() async {
    final f = await showModalBottomSheet<StationFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _FilterSheet(
        initial: _filter,
        connectors: StationSearch.availableConnectors(_result?.stations ?? const []),
      ),
    );
    if (f != null && mounted) {
      setState(() {
        _filter = f;
        _recompute();
      });
    }
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _mapView()),
          if (_listMode) Positioned.fill(child: _listView()),
          // Thanh trên cùng: tìm kiếm + bộ lọc
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _searchBar(canPop),
                    const SizedBox(height: 8),
                    _filterRow(),
                    if (_searchFocus.hasFocus || _places.isNotEmpty || _searchingPlace || _placeError != null)
                      _suggestions(),
                  ],
                ),
              ),
            ),
          ),
          if (!_listMode) ...[
            Positioned(right: 12, bottom: _bottomInset + 12, child: _mapButtons()),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel()),
          ],
          if (_loading)
            const Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: LinearProgressIndicator(minHeight: 3))),
        ],
      ),
    );
  }

  double get _bottomInset => _route != null ? 250 : 210;

  BoxDecoration _glass({double radius = AppRadius.lg}) => BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.panelBorderBright),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
      );

  Widget _searchBar(bool canPop) {
    return Container(
      height: 52,
      decoration: _glass(radius: AppRadius.pill),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              tooltip: 'Quay lại',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.search_rounded),
            ),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _centerName == null ? 'Tìm trạm, địa chỉ, tỉnh/thành…' : 'Đang tìm quanh: $_centerName',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          if (_searchCtl.text.isNotEmpty || _filter.query.isNotEmpty || _center != null)
            IconButton(tooltip: 'Xóa tìm kiếm', icon: const Icon(Icons.close_rounded), onPressed: _clearSearch),
          IconButton(
            tooltip: 'Trạm đã lưu & lịch sử',
            icon: Badge(
              isLabelVisible: _favIds.isNotEmpty,
              label: Text('${_favIds.length}'),
              child: const Icon(Icons.star_outline_rounded),
            ),
            onPressed: _openSaved,
          ),
          IconButton(
            tooltip: _listMode ? 'Xem bản đồ' : 'Xem danh sách',
            icon: Icon(_listMode ? Icons.map_rounded : Icons.view_list_rounded),
            onPressed: () => setState(() => _listMode = !_listMode),
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final r in _radii)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(r == null ? 'Tất cả khu vực' : 'Trong ${r.toInt()} km'),
                selected: _filter.radiusKm == r,
                onSelected: (_) => _setRadius(r),
                backgroundColor: AppColors.panel,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ActionChip(
            avatar: Badge(
              isLabelVisible: _filter.advancedCount > 0,
              label: Text('${_filter.advancedCount}'),
              child: const Icon(Icons.tune_rounded, size: 18),
            ),
            label: const Text('Bộ lọc'),
            onPressed: _openFilters,
            backgroundColor: AppColors.panel,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _suggestions() {
    final children = <Widget>[];
    if (_searchingPlace) {
      children.add(const Padding(
        padding: EdgeInsets.all(14),
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Đang tìm địa điểm…'),
        ]),
      ));
    }
    if (_placeError != null) {
      children.add(Padding(
        padding: const EdgeInsets.all(14),
        child: Text(_placeError!, style: TextStyle(color: AppColors.redText, fontSize: 13)),
      ));
    }
    for (final p in _places) {
      children.add(ListTile(
        dense: true,
        leading: const Icon(Icons.place_outlined),
        title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Tìm trạm sạc quanh địa điểm này'),
        onTap: () => _pickPlace(p),
      ));
    }
    if (_places.isEmpty && !_searchingPlace && _placeError == null && _searchCtl.text.isEmpty) {
      if (_history.isEmpty) {
        children.add(const Padding(
          padding: EdgeInsets.all(14),
          child: Text('Nhập tên trạm, địa chỉ hoặc tỉnh/thành rồi bấm tìm.'),
        ));
      }
      for (final h in _history.take(6)) {
        children.add(ListTile(
          dense: true,
          leading: const Icon(Icons.history_rounded),
          title: Text(h),
          onTap: () {
            _searchCtl.text = h;
            _submitSearch(h);
          },
        ));
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: _glass(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: children),
      ),
    );
  }

  Widget _mapView() {
    final me = _me;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: me ?? const LatLng(16.0, 106.0),
        initialZoom: me == null ? 5 : 14,
        onLongPress: (_, p) => _routeToDestination(p),
        onTap: (_, __) => _searchFocus.unfocus(),
      ),
      children: [
        MapTileService.buildTileLayer(style: MapTileStyle.fastCdn),
        if (_route != null)
          PolylineLayer(polylines: [
            Polyline(points: _route!.points, strokeWidth: 6, color: AppColors.primaryFill.withValues(alpha: 0.85)),
          ]),
        MarkerLayer(markers: [
          for (final h in _hits)
            Marker(
              point: h.station.position,
              width: 44,
              height: 44,
              child: GestureDetector(
                onTap: () => _select(h.station),
                child: StationMarker(
                  station: h.station,
                  selected: _selected?.id == h.station.id || _stop?.station.id == h.station.id || _target?.id == h.station.id,
                  favorite: _favIds.contains(h.station.id),
                ),
              ),
            ),
          if (_center != null)
            Marker(point: _center!, width: 40, height: 40, child: Icon(Icons.location_searching_rounded, color: AppColors.primary, size: 32)),
          if (_dest != null) Marker(point: _dest!, width: 40, height: 40, child: Icon(Icons.flag_rounded, color: AppColors.red, size: 34)),
          if (me != null)
            Marker(
              point: me,
              width: 40,
              height: 40,
              child: Transform.rotate(
                angle: ((_heading ?? 0) * math.pi / 180),
                child: Icon(Icons.navigation_rounded, color: AppColors.primary, size: 32),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _mapButtons() {
    Widget btn(IconData i, String tip, VoidCallback f) => Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: _glass(radius: AppRadius.md),
          child: IconButton(tooltip: tip, icon: Icon(i), onPressed: f),
        );
    return Column(
      children: [
        btn(Icons.add_rounded, 'Phóng to', () => _safeMove(_map.camera.center, _cameraZoom + 1)),
        btn(Icons.remove_rounded, 'Thu nhỏ', () => _safeMove(_map.camera.center, _cameraZoom - 1)),
        btn(Icons.my_location_rounded, 'Định vị lại', _recenter),
      ],
    );
  }

  // ───────────── Panel dưới bản đồ ─────────────

  Widget _bottomPanel() {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _banners(),
          if (_route != null) _routePanel() else _cardStrip(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _banners() {
    final out = <Widget>[];
    Widget banner(String t, Color c, {String? action, VoidCallback? onAction, IconData icon = Icons.info_outline_rounded}) =>
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: c.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.readable(c)),
              const SizedBox(width: 8),
              Expanded(child: Text(t, style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.3))),
              if (action != null) TextButton(onPressed: onAction, child: Text(action)),
            ],
          ),
        );
    if (_locError != null) {
      out.add(banner(
        _locError!,
        AppColors.amber,
        icon: Icons.location_off_rounded,
        action: _permDenied ? 'Cài đặt' : 'Thử lại',
        onAction: () {
          if (_permDenied) {
            Geolocator.openAppSettings();
          } else {
            _startLocation();
          }
        },
      ));
    }
    final r = _result;
    if (r != null && r.fromCache) {
      out.add(banner(
        'Không có mạng hoặc máy chủ lỗi — đang hiện dữ liệu đã lưu lúc ${r.cachedAt == null ? 'không rõ' : StationUi.dateTime(r.cachedAt!)}.',
        AppColors.amber,
        icon: Icons.wifi_off_rounded,
        action: 'Tải lại',
        onAction: _loadStations,
      ));
    }
    if (_error != null && _route == null && (r == null || r.stations.isEmpty)) {
      out.add(banner(_error!, AppColors.red, icon: Icons.error_outline_rounded, action: 'Tải lại', onAction: _loadStations));
    } else if (_error != null && _route != null) {
      out.add(banner(_error!, AppColors.red, icon: Icons.error_outline_rounded));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: out);
  }

  Widget _cardStrip() {
    if (_hits.isEmpty) {
      if (_loading || _result == null && _origin != null) {
        return const SizedBox(height: 0);
      }
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _glass(),
        child: StateView(
          kind: StateKind.empty,
          compact: true,
          icon: Icons.ev_station_outlined,
          title: _origin == null ? 'Chưa có vị trí để tìm trạm' : 'Không có trạm phù hợp',
          message: _origin == null
              ? 'Cấp quyền vị trí hoặc tìm theo tên, địa chỉ, tỉnh/thành.'
              : 'Thử tăng bán kính, bỏ bớt bộ lọc, hoặc tìm ở khu vực khác. '
                  'Trạm ô tô và trạm chưa rõ loại xe có thể đang bị ẩn.',
          actionLabel: _filter.radiusKm == null ? null : 'Tìm trong tất cả khu vực',
          onAction: _filter.radiusKm == null ? null : () => _setRadius(null),
        ),
      );
    }
    final pct = _livePercent;
    final cons = _consumption;
    return SizedBox(
      height: 170,
      child: ListView.separated(
        controller: _cards,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: math.min(_hits.length, 40),
        separatorBuilder: (_, __) => const SizedBox(width: _kCardGap),
        itemBuilder: (_, i) => SizedBox(
          width: _kCardW,
          child: _stationCard(_hits[i], pct, cons),
        ),
      ),
    );
  }

  Widget _stationCard(StationHit h, int? pct, ConsumptionEstimate? cons, {bool full = false}) {
    final s = h.station;
    final sel = _selected?.id == s.id;
    final vc = StationUi.vehicleColor(s.vehicle);
    ReachAssessment? reach;
    if (h.km != null && _center == null) {
      reach = ReachEstimator.assess(straightKm: h.km!, percent: pct, consumption: cons);
    }
    final specs = <String>[
      if (s.powerKw != null) '${s.powerKw!.toStringAsFixed(s.powerKw! % 1 == 0 ? 0 : 1)} kW',
      if (s.ports != null) '${s.ports} cổng',
      if (s.sockets != null) s.sockets!,
    ];
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: sel ? vc : AppColors.panelBorderBright, width: sel ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => sel || full ? _openDetail(s) : _select(s, scrollCard: false),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 16, backgroundColor: vc, child: Icon(StationUi.vehicleIcon(s.vehicle), size: 18, color: Colors.white)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _favIds.contains(s.id) ? 'Bỏ yêu thích' : 'Lưu yêu thích',
                    icon: Icon(
                      _favIds.contains(s.id) ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: _favIds.contains(s.id) ? AppColors.amber : AppColors.textSecondary,
                    ),
                    onPressed: () => _toggleFav(s),
                  ),
                ],
              ),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StationChip(icon: Icons.circle, label: StationUi.statusLabel(s.status), color: StationUi.statusColor(s.status)),
                StationChip(icon: StationUi.vehicleIcon(s.vehicle), label: StationUi.vehicleLabel(s.vehicle), color: vc),
              ]),
              Text(
                [
                  if (h.km != null) '${StationUi.km(h.km!)} (chim bay)',
                  specs.isEmpty ? 'Chưa có dữ liệu công suất/đầu sạc' : specs.join(' · '),
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.carOnly
                          ? 'Không dành cho xe máy điện'
                          : (reach == null ? ' ' : reach.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: s.carOnly
                            ? AppColors.redText
                            : switch (reach?.level) {
                                ReachLevel.likely => AppColors.greenText,
                                ReachLevel.tight => AppColors.amberText,
                                ReachLevel.risky || ReachLevel.unlikely => AppColors.redText,
                                _ => AppColors.textSecondary,
                              },
                      ),
                    ),
                  ),
                  TextButton(onPressed: () => _openDetail(s), child: const Text('Chi tiết')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────── Chế độ danh sách ─────────────

  Widget _listView() {
    final pct = _livePercent;
    final cons = _consumption;
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 112),
          child: _hits.isEmpty
              ? ListView(children: [
                  StateView(
                    kind: _loading ? StateKind.loading : StateKind.empty,
                    icon: Icons.ev_station_outlined,
                    title: _loading ? 'Đang tìm trạm sạc…' : 'Không có trạm phù hợp',
                    message: _loading ? null : 'Thử tăng bán kính hoặc bỏ bớt bộ lọc.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: _hits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => SizedBox(height: 170, child: _stationCard(_hits[i], pct, cons, full: true)),
                ),
        ),
      ),
    );
  }

  // ───────────── Panel tuyến ─────────────

  Widget _routePanel() {
    final r = _route!;
    final me = _me;
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
    String batt;
    var notEnough = false;
    if (pct == null) {
      batt = 'Pin đến nơi: không có dữ liệu pin trực tiếp từ xe.';
    } else if (cons == null) {
      batt = 'Pin hiện tại $pct% — chưa đủ dữ liệu để ước tính tiêu hao.';
    } else {
      final after = EnergyEstimator.batteryAfter(pct.toDouble(), remainingKm, cons.percentPerKm);
      notEnough = after < 0;
      batt = 'Pin đến nơi (ước tính): ${after.clamp(-99, 100).toStringAsFixed(0)}%${notEnough ? ' — KHÔNG ĐỦ' : ''} · cơ sở: ${cons.basis}';
    }
    final etaMin = (r.durationS / 60).round();
    final target = _target ?? _stop?.station;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: _glass(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.turn_right_rounded, size: 30, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step?.instruction ?? 'Đang theo tuyến',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
              if (toStepM != null)
                Text(toStepM >= 1000 ? '${(toStepM / 1000).toStringAsFixed(1)} km' : '${toStepM.round()} m',
                    style: TextStyle(color: AppColors.textSecondary)),
              IconButton(tooltip: 'Xóa tuyến', icon: const Icon(Icons.close_rounded), onPressed: _clearRoute),
            ],
          ),
          Text(
            'Còn ${remainingKm.toStringAsFixed(1)} km · tổng ${r.distanceKm.toStringAsFixed(1)} km · ~$etaMin phút '
            '(tính theo ô tô, chỉ tham khảo)',
            style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(batt, style: TextStyle(fontSize: 12, color: notEnough ? AppColors.redText : AppColors.textSecondary)),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_note!, style: TextStyle(fontSize: 12, color: AppColors.amberText, height: 1.3)),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (target != null)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final ok = await ExternalNav.navigateTo(target.position, target.name);
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Không mở được ứng dụng bản đồ trên máy.')));
                      }
                    },
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text('Mở ứng dụng bản đồ'),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Chỉ dẫn chỉ là văn bản theo GPS điện thoại, không có giọng nói và không tự dẫn lại. Không thao tác điện thoại khi đang lái.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════ Bộ lọc nâng cao ═════════════

class _FilterSheet extends StatefulWidget {
  final StationFilter initial;
  final List<String> connectors;
  const _FilterSheet({required this.initial, required this.connectors});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late StationFilter f = widget.initial;
  static const _powers = <double>[0, 3.3, 7, 22, 50];

  @override
  Widget build(BuildContext context) {
    final title = GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bộ lọc trạm sạc', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            Text('Chuẩn đầu nối', style: title),
            const SizedBox(height: 6),
            if (widget.connectors.isEmpty)
              Text('Dữ liệu trạm đã tải chưa ghi chuẩn đầu nối nào.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
            else
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: const Text('Tất cả'),
                  selected: f.connector.isEmpty,
                  onSelected: (_) => setState(() => f = f.copyWith(connector: '')),
                ),
                for (final c in widget.connectors)
                  ChoiceChip(
                    label: Text(c),
                    selected: f.connector == c,
                    onSelected: (_) => setState(() => f = f.copyWith(connector: c)),
                  ),
              ]),
            const SizedBox(height: 14),
            Text('Công suất tối thiểu', style: title),
            const SizedBox(height: 2),
            Text('Trạm không có dữ liệu công suất sẽ bị ẩn khi chọn mức này.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final p in _powers)
                ChoiceChip(
                  label: Text(p == 0 ? 'Bất kỳ' : '≥ ${p % 1 == 0 ? p.toInt() : p} kW'),
                  selected: f.minPowerKw == p,
                  onSelected: (_) => setState(() => f = f.copyWith(minPowerKw: p)),
                ),
            ]),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Chỉ trạm mở cửa 24/7'),
              subtitle: const Text('Chỉ tính trạm có giờ mở ghi rõ 24/7.'),
              value: f.only24h,
              onChanged: (v) => setState(() => f = f.copyWith(only24h: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hiện trạm chưa rõ loại xe'),
              subtitle: const Text('Nguồn không nói trạm có sạc được xe máy điện — cần xác nhận trước khi đến.'),
              value: f.includeUnknownVehicle,
              onChanged: (v) => setState(() => f = f.copyWith(includeUnknownVehicle: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hiện cả trạm ô tô điện'),
              subtitle: const Text('Được đánh dấu "không dành cho xe máy điện".'),
              value: f.includeCarOnly,
              onChanged: (v) => setState(() => f = f.copyWith(includeCarOnly: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ẩn trạm đã đóng cửa'),
              value: f.hideClosed,
              onChanged: (v) => setState(() => f = f.copyWith(hideClosed: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => f = StationFilter(radiusKm: f.radiusKm, query: f.query)),
                    child: const Text('Đặt lại'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: () => Navigator.of(context).pop(f), child: const Text('Áp dụng')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════ Đã lưu · Đã dùng · Lịch sử (đọc từ máy, dùng được khi offline) ═════════════

class _SavedSheet extends StatefulWidget {
  const _SavedSheet();

  @override
  State<_SavedSheet> createState() => _SavedSheetState();
}

class _SavedSheetState extends State<_SavedSheet> {
  List<ChargingStation> _fav = const [];
  List<UsedStation> _used = const [];
  List<String> _hist = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final f = await StationUserStore.favorites();
    final u = await StationUserStore.used();
    final h = await StationUserStore.history();
    if (mounted) {
      setState(() {
        _fav = f;
        _used = u;
        _hist = h;
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const TabBar(tabs: [
              Tab(text: 'Yêu thích'),
              Tab(text: 'Đã sạc'),
              Tab(text: 'Lịch sử tìm'),
            ]),
            Expanded(
              child: !_ready
                  ? const StateView(kind: StateKind.loading, title: 'Đang đọc dữ liệu đã lưu…')
                  : TabBarView(children: [
                      _stationList(
                        [for (final s in _fav) (s, null)],
                        'Chưa có trạm yêu thích',
                        'Bấm biểu tượng ngôi sao trên thẻ trạm để lưu. Danh sách này xem được cả khi mất mạng.',
                      ),
                      _stationList(
                        [for (final u in _used) (u.station, u.at)],
                        'Chưa đánh dấu trạm nào',
                        'Mở chi tiết trạm và bấm "Tôi đã sạc ở đây" để ghi lại.',
                      ),
                      _history(),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stationList(List<(ChargingStation, DateTime?)> items, String emptyTitle, String emptyMsg) {
    if (items.isEmpty) {
      return StateView(kind: StateKind.empty, icon: Icons.star_outline_rounded, title: emptyTitle, message: emptyMsg);
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.panelBorder),
      itemBuilder: (_, i) {
        final s = items[i].$1;
        final at = items[i].$2;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: StationUi.vehicleColor(s.vehicle),
            child: Icon(StationUi.vehicleIcon(s.vehicle), color: Colors.white, size: 20),
          ),
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              StationUi.vehicleLabel(s.vehicle),
              if (at != null) 'sạc lúc ${StationUi.dateTime(at)}',
              if (s.address != null) s.address!,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(s),
        );
      },
    );
  }

  Widget _history() {
    if (_hist.isEmpty) {
      return const StateView(kind: StateKind.empty, icon: Icons.history_rounded, title: 'Chưa có lịch sử tìm kiếm');
    }
    return ListView(
      children: [
        for (final h in _hist)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(h),
            onTap: () => Navigator.of(context).pop(h),
          ),
        TextButton.icon(
          onPressed: () async {
            await StationUserStore.clearHistory();
            _reload();
          },
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Xóa lịch sử tìm kiếm'),
        ),
      ],
    );
  }
}
