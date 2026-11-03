// Thẻ thống kê hành trình theo Ngày / Tuần / Tháng (tab VEHICLE).
// Chỉ đọc bleProvider.tripHistory. Không có chuyến → trạng thái trống, không bịa số.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/trips/trip_stats.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';

class TripStatsCard extends ConsumerStatefulWidget {
  const TripStatsCard({super.key});

  @override
  ConsumerState<TripStatsCard> createState() => _TripStatsCardState();
}

class _TripStatsCardState extends ConsumerState<TripStatsCard> {
  TripPeriod _p = TripPeriod.day;

  static String _label(TripPeriod p, DateTime d) {
    switch (p) {
      case TripPeriod.day:
        return '${d.day}/${d.month}';
      case TripPeriod.week:
        return '${d.day}/${d.month}';
      case TripPeriod.month:
        return 'T${d.month}';
    }
  }

  static String _dur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '$h giờ $m phút' : '$m phút';
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(bleProvider.select((s) => s.tripHistory));
    final st = TripStats.compute(trips, _p, DateTime.now());
    final maxKm = st.buckets.fold<double>(0, (a, b) => b.km > a ? b.km : a);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TripPeriod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TripPeriod.day, label: Text('Ngày')),
                ButtonSegment(value: TripPeriod.week, label: Text('Tuần')),
                ButtonSegment(value: TripPeriod.month, label: Text('Tháng')),
              ],
              selected: {_p},
              onSelectionChanged: (v) => setState(() => _p = v.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (st.trips == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('Chưa có hành trình nào trong khoảng thời gian này.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(color: AppColors.textSecondary)),
              )
            else ...[
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _kv('Tổng quãng đường', '${st.totalKm.toStringAsFixed(1)} km'),
                  _kv('Số chuyến', '${st.trips}'),
                  _kv('Thời gian', _dur(st.totalSec)),
                  _kv('Tốc độ TB',
                      st.avgSpeedKmh == null ? 'N/A' : '${st.avgSpeedKmh!.toStringAsFixed(0)} km/h'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final b in st.buckets)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: maxKm <= 0 ? 2 : (b.km / maxKm * 64).clamp(2, 64).toDouble(),
                                decoration: BoxDecoration(
                                  color: b.km > 0
                                      ? AppColors.primary
                                      : AppColors.panelBorder,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(_label(_p, b.start),
                                  maxLines: 1,
                                  style: AppTypography.labelSm(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: AppTypography.labelSm(color: AppColors.textSecondary)),
          Text(v, style: AppTypography.labelLg()),
        ],
      );
}
