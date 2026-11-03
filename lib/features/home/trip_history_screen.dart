// Lịch sử hành trình (mở từ tab MAP): danh sách chuyến đã ghi, lọc Hôm nay / Tuần /
// Tháng / Tất cả, tổng quãng đường. Chạm một chuyến → TripRouteScreen (bản đồ + phát lại).
// Chỉ đọc bleProvider.tripHistory. Chuyến không có tuyến GPS được ghi rõ, không vẽ tuyến giả.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/trips/trip_stats.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import 'trip_route_screen.dart';

class TripHistoryScreen extends ConsumerStatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  ConsumerState<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends ConsumerState<TripHistoryScreen> {
  TripPeriod? _p = TripPeriod.week; // null = tất cả

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '$h giờ $m phút' : (m > 0 ? '$m phút' : '$s giây');
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(bleProvider.select((s) => s.tripHistory));
    final shown = tripsInCurrentPeriod(all, _p, DateTime.now());
    final km = shown.fold<double>(0, (a, t) => a + t.distanceKm);

    Widget chip(String label, TripPeriod? v) => ChoiceChip(
          label: Text(label),
          selected: _p == v,
          onSelected: (_) => setState(() => _p = v),
        );

    return DsScaffold(
      title: 'Lịch sử hành trình',
      subtitle: '${shown.length} chuyến · ${km.toStringAsFixed(1)} km',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.huge),
        children: [
          Wrap(spacing: AppSpacing.sm, children: [
            chip('Hôm nay', TripPeriod.day),
            chip('Tuần này', TripPeriod.week),
            chip('Tháng này', TripPeriod.month),
            chip('Tất cả', null),
          ]),
          const SizedBox(height: AppSpacing.md),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
              child: Text(
                all.isEmpty
                    ? 'Chưa có hành trình nào được ghi.'
                    : 'Không có hành trình trong khoảng thời gian này.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd(color: AppColors.textSecondary),
              ),
            )
          else
            for (final t in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: GlassCard(
                  semanticLabel:
                      'Hành trình ${t.distanceKm.toStringAsFixed(1)} km. Chạm để xem bản đồ',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => TripRouteScreen(
                      trip: t,
                      tripIndex: all.length - all.indexOf(t),
                      allTrips: all,
                    ),
                  )),
                  child: Row(
                    children: [
                      Icon(
                        t.route.isNotEmpty
                            ? Icons.alt_route_rounded
                            : Icons.location_off_outlined,
                        color: t.route.isNotEmpty
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_two(t.startTime.day)}/${_two(t.startTime.month)}/${t.startTime.year} · ${_two(t.startTime.hour)}:${_two(t.startTime.minute)}',
                              style: AppTypography.labelLg(),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${t.distanceKm.toStringAsFixed(1)} km · ${_dur(t.durationSec)} · TB ${t.avgSpeedKmh.toStringAsFixed(0)} km/h · tối đa ${t.maxSpeedKmh.toStringAsFixed(0)} km/h',
                              style: AppTypography.bodySm(),
                            ),
                            if (t.route.isEmpty)
                              Text('Không có dữ liệu tuyến GPS',
                                  style: AppTypography.labelSm(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
