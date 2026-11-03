// Chọn vị trí trạm trực tiếp trên bản đồ: chạm và giữ để đặt Marker, tự lấy
// Vĩ độ/Kinh độ và (nếu có mạng) đổi sang địa chỉ qua Nominatim. Địa chỉ và tọa
// độ vẫn chỉnh sửa được ở màn hình biểu mẫu trước khi lưu.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../core/charging/place_search_service.dart';
import '../../core/services/charging_station_service.dart';
import '../../core/services/map_tile_service.dart';
import '../../ui/app_theme.dart';

class PickedPlace {
  final LatLng position;
  final String? address;
  final String province;
  final String district;
  const PickedPlace(this.position, {this.address, this.province = '', this.district = ''});
}

class StationPickerScreen extends StatefulWidget {
  final LatLng? initial;

  /// Trạm đang có — vẽ làm điểm xám để thấy ngay nếu chọn sát trạm khác.
  final List<ChargingStation> existing;
  final String title;

  const StationPickerScreen({
    super.key,
    this.initial,
    this.existing = const [],
    this.title = 'Chọn vị trí trên bản đồ',
  });

  @override
  State<StationPickerScreen> createState() => _StationPickerScreenState();
}

class _StationPickerScreenState extends State<StationPickerScreen> {
  final MapController _map = MapController();
  LatLng? _picked;
  ReverseHit? _addr;
  bool _geocoding = false;
  bool _geoFailed = false;
  String? _gpsError;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
    if (_picked != null) _reverse(_picked!);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _reverse(LatLng p) async {
    final my = ++_seq;
    setState(() {
      _geocoding = true;
      _geoFailed = false;
      _addr = null;
    });
    final r = await PlaceReverseService.lookup(p.latitude, p.longitude);
    if (!mounted || my != _seq) return;
    setState(() {
      _addr = r;
      _geocoding = false;
      _geoFailed = r == null;
    });
  }

  void _pick(LatLng p) {
    setState(() => _picked = p);
    _reverse(p);
  }

  Future<void> _myLocation() async {
    setState(() => _gpsError = null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gpsError = 'GPS đang tắt. Bật vị trí hoặc chạm giữ trên bản đồ.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gpsError = 'Chưa được cấp quyền vị trí. Hãy chạm giữ trên bản đồ để chọn.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final ll = LatLng(p.latitude, p.longitude);
      try {
        _map.move(ll, 17);
      } catch (_) {}
      _pick(ll);
    } catch (_) {
      if (mounted) setState(() => _gpsError = 'Không lấy được vị trí hiện tại.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final dark = AppColors.isDark;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: widget.initial ?? const LatLng(16.0, 106.0),
              initialZoom: widget.initial == null ? 5 : 16,
              minZoom: 3,
              maxZoom: 19,
              onLongPress: (_, p) => _pick(p),
            ),
            children: [
              MapTileService.buildTileLayer(style: dark ? MapTileStyle.darkEv : MapTileStyle.fastCdn),
              MarkerLayer(markers: [
                for (final s in widget.existing)
                  Marker(
                    point: s.position,
                    width: 14,
                    height: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.withValues(alpha: 0.85),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                if (picked != null)
                  Marker(
                    point: picked,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_on_rounded, size: 44, color: Color(0xFFDC2626)),
                  ),
              ]),
            ],
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.panel.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.panelBorderBright),
              ),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chạm và giữ trên bản đồ để đặt Marker. Điểm xám là trạm đã có.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 200,
            child: FloatingActionButton.small(
              heroTag: 'picker_gps',
              tooltip: 'Vị trí của tôi',
              onPressed: _myLocation,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.panelBorderBright),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (picked == null)
                      Text('Chưa chọn vị trí.',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textPrimary))
                    else ...[
                      Text(
                        '${picked.latitude.toStringAsFixed(6)}, ${picked.longitude.toStringAsFixed(6)}',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      if (_geocoding)
                        const Row(children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Đang lấy địa chỉ…'),
                        ])
                      else if (_addr != null)
                        Text(_addr!.address, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
                      else if (_geoFailed)
                        Text('Không lấy được địa chỉ tự động (mất mạng hoặc không có dữ liệu). Bạn nhập địa chỉ ở bước sau.',
                            style: TextStyle(fontSize: 12.5, color: AppColors.amberText)),
                    ],
                    if (_gpsError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_gpsError!, style: TextStyle(fontSize: 12.5, color: AppColors.redText)),
                      ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: picked == null
                          ? null
                          : () => Navigator.of(context).pop(PickedPlace(
                                picked,
                                address: _addr?.address,
                                province: _addr?.province ?? '',
                                district: _addr?.district ?? '',
                              )),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Dùng vị trí này'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
