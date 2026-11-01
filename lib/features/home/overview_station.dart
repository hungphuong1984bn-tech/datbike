// Thẻ "Trạm sạc gần nhất" của tab Tổng quan.
//
// Nguồn dữ liệu DUY NHẤT: kết quả tìm trạm gần nhất đã lưu (OpenStreetMap, qua
// ChargingStationService). Thẻ KHÔNG gọi mạng, KHÔNG tự xin quyền vị trí.
//
//  • Khoảng cách chỉ hiện khi vị trí điện thoại ĐÃ có sẵn (quyền đã cấp và có
//    vị trí gần nhất). Không có → không hiện km, ghi "so với nơi tìm gần nhất".
//  • Không hiển thị số cổng trống, trạng thái hoạt động, giá hay tương thích nếu
//    nguồn không cung cấp (OSM mặc định "chưa xác minh").
//  • Chưa từng tìm trạm → trạng thái rỗng, mời mở tab Trạm sạc.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/charging/station_repository.dart';
import '../../core/services/charging_station_service.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';
import '../navigation/charge_finder_screen.dart';

/// Kết quả chọn trạm gần nhất (hàm thuần → dễ kiểm thử).
class NearestStation {
  final ChargingStation station;

  /// Khoảng cách (km) tới VỊ TRÍ ĐIỆN THOẠI; null nếu chưa biết vị trí.
  final double? distanceKm;

  /// Khoảng cách tới điểm tìm kiếm gần nhất (dùng để xếp hạng khi không có vị trí).
  final double fromSearchKm;

  const NearestStation(this.station, this.distanceKm, this.fromSearchKm);
}

/// Chọn trạm gần nhất. [me] != null → xếp theo khoảng cách tới điện thoại,
/// ngược lại xếp theo khoảng cách tới điểm tìm kiếm [searchCenter].
NearestStation? pickNearestStation(
  List<ChargingStation> stations, {
  required LatLng searchCenter,
  LatLng? me,
}) {
  if (stations.isEmpty) return null;
  const d = Distance();
  NearestStation? best;
  var bestKey = double.infinity;
  for (final s in stations) {
    final p = LatLng(s.lat, s.lng);
    final fromSearch = d.as(LengthUnit.Kilometer, searchCenter, p);
    final fromMe = me == null ? null : d.as(LengthUnit.Kilometer, me, p);
    final key = fromMe ?? fromSearch;
    if (key < bestKey) {
      bestKey = key;
      best = NearestStation(s, fromMe, fromSearch);
    }
  }
  return best;
}

class _Loaded {
  final NearestStation? nearest;
  final DateTime? at;
  const _Loaded(this.nearest, this.at);
}

class OverviewNearestStation extends StatefulWidget {
  const OverviewNearestStation({super.key});

  @override
  State<OverviewNearestStation> createState() => _OverviewNearestStationState();
}

class _OverviewNearestStationState extends State<OverviewNearestStation> {
  late final Future<_Loaded> _future = _load();

  Future<_Loaded> _load() async {
    final cache = await StationRepository.loadLastRegion();
    if (cache == null || cache.stations.isEmpty) return const _Loaded(null, null);

    // Chỉ dùng vị trí đã có sẵn; tuyệt đối không bật hộp thoại xin quyền ở đây.
    LatLng? me;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) me = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {
      me = null; // nền tảng không hỗ trợ / lỗi → coi như chưa biết vị trí
    }

    final nearest = pickNearestStation(
      cache.stations,
      searchCenter: LatLng(cache.lat, cache.lng),
      me: me,
    );
    return _Loaded(nearest, cache.at);
  }

  void _openFinder() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChargeFinderScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Trạm sạc gần nhất',
          action: TextButton(
            onPressed: _openFinder,
            style: TextButton.styleFrom(
              minimumSize: const Size(AppSizes.minTap, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Xem tất cả'),
          ),
        ),
        const SizedBox(height: 6),
        FutureBuilder<_Loaded>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const GlassCard(
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              );
            }
            final data = snap.data;
            final n = data?.nearest;
            if (n == null) return _empty();
            return _card(n, data!.at);
          },
        ),
      ],
    );
  }

  Widget _empty() {
    return GlassCard(
      onTap: _openFinder,
      child: Row(
        children: [
          Icon(Icons.ev_station_outlined, size: 28, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chưa có dữ liệu trạm sạc',
                    style: AppTypography.labelLg(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Mở bản đồ để tìm trạm sạc quanh bạn.',
                    style: AppTypography.bodySm(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _card(NearestStation n, DateTime? cachedAt) {
    final s = n.station;
    final dist = n.distanceKm;
    final meta = <String>[
      if (s.isVinFast) 'VinFast / V-GREEN',
      if (s.powerKw != null) 'Tối đa ${s.powerKw!.toStringAsFixed(s.powerKw! % 1 == 0 ? 0 : 1)} kW',
      if (s.sockets != null) s.sockets!,
    ];
    return GlassCard(
      semanticLabel: 'Trạm sạc gần nhất: ${s.name}'
          '${dist == null ? '' : ', cách ${dist.toStringAsFixed(1)} ki-lô-mét'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.greenSoftBorder),
                ),
                child: Icon(Icons.ev_station_rounded, color: AppColors.greenText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLg(color: AppColors.textPrimary)
                            .copyWith(fontWeight: FontWeight.w700)),
                    if (s.address != null) ...[
                      const SizedBox(height: 2),
                      Text(s.address!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySm(color: AppColors.textSecondary)),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySm(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (dist != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(dist.toStringAsFixed(1),
                        style: AppTypography.evWide(fontSize: 20, letterSpacing: -0.3)),
                    Text('km', style: AppTypography.labelMd(color: AppColors.textSecondary)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dist == null
                ? 'Gần nơi tìm kiếm gần nhất · chưa có vị trí hiện tại'
                : 'Tính từ vị trí gần nhất của điện thoại',
            style: AppTypography.labelSm(color: AppColors.textMuted),
          ),
          Text(
            'Nguồn ${s.source}${cachedAt == null ? '' : ' · lưu ${cachedAt.day.toString().padLeft(2, '0')}/${cachedAt.month.toString().padLeft(2, '0')}'}'
            ' · trạng thái hoạt động chưa xác minh',
            style: AppTypography.labelSm(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: AppSizes.minTap,
            child: FilledButton.icon(
              onPressed: _openFinder,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Mở bản đồ & dẫn đường'),
            ),
          ),
        ],
      ),
    );
  }
}
