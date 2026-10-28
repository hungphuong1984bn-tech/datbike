import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/trip_gps_point.dart';
import '../../../core/services/map_tile_service.dart';
import '../../../core/services/offline_map_service.dart';
import '../../../core/services/trip_gps_tracker.dart';
import '../../../ui/app_theme.dart';
import 'offline_map_sheet.dart';

/// Widget Bản Đồ Lái Xe Thời Gian Thực (Live GPS Cockpit Map) trên Dashboard
/// Thiết kế đồng bộ hoàn hảo theo ngôn ngữ Kinetic Stitch EV (Pure White Card, Hairline Border, Space Grotesk)
class CockpitLiveMap extends StatefulWidget {
  final double currentSpeedKmh;
  final VoidCallback? onExpandFullScreen;

  const CockpitLiveMap({
    super.key,
    required this.currentSpeedKmh,
    this.onExpandFullScreen,
  });

  @override
  State<CockpitLiveMap> createState() => _CockpitLiveMapState();
}

class _CockpitLiveMapState extends State<CockpitLiveMap> {
  late final MapController _mapController;
  StreamSubscription<TripGpsPoint>? _pointSub;
  List<TripGpsPoint> _liveRoute = [];

  MapTileStyle _tileStyle = MapTileStyle.fastCdn; // Mặc định OSM-FR sáng đồng bộ Kinetic Stitch EV
  bool _followBike = true;
  bool _isLocating = false;
  LatLng? _myLocation;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _liveRoute = TripGpsTracker.instance.getCurrentRoute();

    // Lắng nghe điểm GPS mới khi xe di chuyển trong thời gian thực
    _pointSub = TripGpsTracker.instance.onPointRecorded.listen((newPoint) {
      if (!mounted) return;
      setState(() {
        _liveRoute.add(newPoint);
        _myLocation = LatLng(newPoint.lat, newPoint.lng);
      });
      if (_followBike) {
        _mapController.move(LatLng(newPoint.lat, newPoint.lng), _mapController.camera.zoom);
      }
    });

    // Lấy ngay vị trí hiện tại khi vừa mở dashboard
    _locateMe(moveCamera: false);
  }

  @override
  void dispose() {
    _pointSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locateMe({bool moveCamera = true}) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    final pos = await TripGpsTracker.instance.getCurrentLocation();
    if (!mounted) return;
    setState(() => _isLocating = false);

    if (pos != null) {
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = loc);
      if (moveCamera) {
        _mapController.move(loc, 16.5);
      }
    }
  }

  void _cycleTileStyle() {
    setState(() {
      const styles = MapTileStyle.values;
      final nextIndex = (styles.indexOf(_tileStyle) + 1) % styles.length;
      _tileStyle = styles[nextIndex];
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bản đồ: ${MapTileService.getStyleName(_tileStyle)} (100% Free)'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.textPrimary,
      ),
    );
  }

  Color _getContinuousSpeedColor(double speedKmh) {
    if (speedKmh <= 15.0) {
      final t = (speedKmh / 15.0).clamp(0.0, 1.0);
      return Color.lerp(const Color(0xFF06B6D4), const Color(0xFF10B981), t)!;
    } else if (speedKmh <= 35.0) {
      final t = ((speedKmh - 15.0) / 20.0).clamp(0.0, 1.0);
      return Color.lerp(const Color(0xFF10B981), const Color(0xFF0EA5E9), t)!;
    } else if (speedKmh <= 55.0) {
      final t = ((speedKmh - 35.0) / 20.0).clamp(0.0, 1.0);
      return Color.lerp(const Color(0xFFF59E0B), const Color(0xFFF97316), t)!;
    } else {
      final t = ((speedKmh - 55.0) / 30.0).clamp(0.0, 1.0);
      return Color.lerp(const Color(0xFFF97316), const Color(0xFFEF4444), t)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRoute = _liveRoute.isNotEmpty;
    final lastPoint = hasRoute ? _liveRoute.last : null;
    final isTracking = TripGpsTracker.instance.isTracking;

    final centerCoord = _myLocation ??
        (lastPoint != null
            ? LatLng(lastPoint.lat, lastPoint.lng)
            : const LatLng(10.7719, 106.7195));

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.panelBorderBright, width: 1),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. BẢN ĐỒ FLUTTER_MAP THỜI GIAN THỰC
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerCoord,
              initialZoom: 16.0,
            ),
            children: [
              // Tile Layer (Ưu tiên nạp từ ổ cứng offline cache)
              MapTileService.buildTileLayer(style: _tileStyle),

              // Polyline Lộ trình đang di chuyển (Live Speed Heatmap với gradient mượt mà)
              if (hasRoute) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _liveRoute.map((p) => LatLng(p.lat, p.lng)).toList(),
                      strokeWidth: 8.0,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                      color: AppColors.primary.withValues(alpha: 0.22),
                    ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    for (int i = 0; i < _liveRoute.length - 1; i++)
                      Polyline(
                        points: [
                          LatLng(_liveRoute[i].lat, _liveRoute[i].lng),
                          LatLng(_liveRoute[i + 1].lat, _liveRoute[i + 1].lng),
                        ],
                        strokeWidth: 5.0,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                        gradientColors: [
                          _getContinuousSpeedColor(_liveRoute[i].speedKmh),
                          _getContinuousSpeedColor(_liveRoute[i + 1].speedKmh),
                        ],
                      ),
                  ],
                ),
              ],

              // Marker Vị trí xe Dat Bike
              MarkerLayer(
                markers: [
                  if (_myLocation != null || lastPoint != null)
                    Marker(
                      point: _myLocation ?? LatLng(lastPoint!.lat, lastPoint.lng),
                      width: 52,
                      height: 52,
                      child: _buildLiveBikeMarker(
                        widget.currentSpeedKmh,
                        lastPoint?.heading ?? 0.0,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. HEADER TOP: Trạng thái REC ghi nhận & Các nút chức năng (Pure White Glass Pill)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                // Badge Trạng thái ghi GPS (REC)
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9999),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.panel.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(
                            color: isTracking
                                ? AppColors.red.withValues(alpha: 0.4)
                                : AppColors.panelBorderBright,
                          ),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isTracking ? AppColors.red : AppColors.tertiary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isTracking ? 'REC ĐANG GHI' : 'GPS SẴN SÀNG',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isTracking ? AppColors.red : AppColors.textPrimary,
                                    letterSpacing: 0.05 * 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Nút đổi Map Tile Style (Tải Nhanh / Đêm EV / Làn xe máy / OSM)
                _miniGlassBtn(
                  icon: MapTileService.getStyleIcon(_tileStyle),
                  tooltip: MapTileService.getStyleName(_tileStyle),
                  onTap: _cycleTileStyle,
                ),
                const SizedBox(width: 6),
                // Nút tải bản đồ offline
                _miniGlassBtn(
                  icon: Icons.download_for_offline_rounded,
                  tooltip: 'Tải bản đồ offline',
                  onTap: () {
                    OfflineMapSheet.show(
                      context,
                      currentMapBounds: _mapController.camera.visibleBounds,
                    );
                  },
                ),
                const SizedBox(width: 6),
                // Nút toàn màn hình
                if (widget.onExpandFullScreen != null)
                  _miniGlassBtn(
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'Toàn màn hình HUD',
                    onTap: widget.onExpandFullScreen!,
                  ),
              ],
            ),
          ),

          // Mini Banner hiển thị trạng thái tải ngầm (Background download tracker)
          ValueListenableBuilder<DownloadProgress>(
            valueListenable: OfflineMapService.instance.progressNotifier,
            builder: (context, progress, _) {
              if (!progress.isRunning && !progress.isPaused) {
                return const SizedBox.shrink();
              }
              return Positioned(
                top: 50,
                left: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => OfflineMapSheet.show(
                    context,
                    currentMapBounds: _mapController.camera.visibleBounds,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9999),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.panel.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(
                            color: progress.isPaused ? AppColors.amber : AppColors.primary,
                          ),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            if (progress.isRunning)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              )
                            else
                              const Icon(Icons.pause_circle_rounded, size: 14, color: AppColors.amber),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                progress.isPaused
                                    ? 'Tạm dừng tải (${progress.percentInt}%)'
                                    : 'Đang tải bản đồ ngầm: ${progress.percentInt}% (${progress.sizeMbText})',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              'Xem >',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 3. CÁC NÚT ĐIỀU HƯỚNG TRÊN BẢN ĐỒ (Bên phải - Clean White Circular Buttons)
          Positioned(
            bottom: 48,
            right: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nút "Vị trí của tôi"
                _miniGlassBtn(
                  icon: Icons.my_location_rounded,
                  iconColor: _isLocating ? AppColors.primary : AppColors.textDim,
                  isActive: _isLocating,
                  tooltip: 'Vị trí của tôi',
                  onTap: () => _locateMe(moveCamera: true),
                ),
                const SizedBox(height: 6),
                // Nút bám theo xe (Follow Bike)
                _miniGlassBtn(
                  icon: Icons.navigation_rounded,
                  iconColor: _followBike ? AppColors.primary : AppColors.textDim,
                  isActive: _followBike,
                  tooltip: _followBike ? 'Đang bám xe' : 'Tự do xoay bản đồ',
                  onTap: () {
                    setState(() => _followBike = !_followBike);
                    if (_followBike && (_myLocation != null || lastPoint != null)) {
                      _mapController.move(
                        _myLocation ?? LatLng(lastPoint!.lat, lastPoint.lng),
                        _mapController.camera.zoom,
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // 4. FOOTER TELEMETRY THỜI GIAN THỰC (Clean White Pill Card)
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.panel.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.panelBorderBright),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      // Vận tốc tức thời
                      Flexible(
                        flex: 4,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                widget.currentSpeedKmh.toStringAsFixed(0),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: widget.currentSpeedKmh > 0 ? AppColors.primary : AppColors.textPrimary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'km/h',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Tọa độ vĩ độ/kinh độ hoặc số điểm
                      Flexible(
                        flex: 6,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.secondary),
                              const SizedBox(width: 3),
                              Text(
                                _myLocation != null
                                    ? '${_myLocation!.latitude.toStringAsFixed(4)}°, ${_myLocation!.longitude.toStringAsFixed(4)}°'
                                    : '${_liveRoute.length} điểm GPS',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildLiveBikeMarker(double speedKmh, double heading) {
    return Transform.rotate(
      angle: (heading * math.pi) / 180.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sóng radar định vị lan tỏa
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
          ),
          // Con trỏ xe Dat Bike
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D2563EB),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.navigation_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniGlassBtn({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color? iconColor,
    bool isActive = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFFEFF6FF) : AppColors.panel.withValues(alpha: 0.92),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.panelBorderBright,
              width: 1,
            ),
            boxShadow: AppColors.cardShadow,
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              icon,
              color: iconColor ?? (isActive ? AppColors.primary : AppColors.textDim),
              size: 16,
            ),
            tooltip: tooltip,
            onPressed: onTap,
          ),
        ),
      ),
    );
  }
}
