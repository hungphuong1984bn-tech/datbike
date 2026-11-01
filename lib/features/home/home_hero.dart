// Thẻ "Tổng quan xe" của trang chủ — Design System v3 (Premium EV).
//
// Bố cục: hàng huy hiệu trạng thái → [ảnh xe | tốc độ] → SOC + quãng đường →
// thanh năng lượng → độ mới dữ liệu → cảnh báo.
//
// Nguyên tắc dữ liệu: chỉ hiển thị giá trị xe đã gửi thật. Giá trị null → "--".
// Không dùng số mẫu. Quãng đường còn lại do app tự ước tính được gắn nhãn "Ước tính".
// Mất kết nối: tốc độ về "--" (không để số cũ trông như đang chạy); SOC/quãng đường
// giữ giá trị cuối kèm nhãn "Dữ liệu cũ".
// Widget chỉ nhận tham số thuần (không đọc BLE) nên dễ kiểm thử và không ảnh hưởng giao thức.

import 'package:flutter/material.dart';

import '../../core/ble/ble_controller.dart' show BlePhase;
import '../../ui/app_theme.dart';
import '../../ui/bike_image.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';

class HomeHeroCard extends StatelessWidget {
  final BlePhase phase;
  final DateTime? lastTelemetryAt;

  // Số liệu thật (null = chưa có)
  final int? percent;
  final int? kmLeft;
  final bool kmEstimated;
  final double? speedKmh;

  // Trạng thái
  final String statusText;
  final String? drivingModeShort;
  final bool isBikeOn;
  final bool isLocked;
  final bool isCharging;
  final double? chargePowerW;
  final bool isSideStandDown;
  final int errorCode;
  final bool isFindingBike;

  // Hành động
  final VoidCallback onStopFind;

  const HomeHeroCard({
    super.key,
    required this.phase,
    required this.lastTelemetryAt,
    required this.percent,
    required this.kmLeft,
    required this.kmEstimated,
    required this.speedKmh,
    required this.statusText,
    required this.drivingModeShort,
    required this.isBikeOn,
    required this.isLocked,
    required this.isCharging,
    required this.chargePowerW,
    required this.isSideStandDown,
    required this.errorCode,
    required this.isFindingBike,
    required this.onStopFind,
  });

  static Color socColor(int? p) {
    if (p == null) return AppColors.textMuted;
    if (p <= 15) return AppColors.red;
    if (p <= 30) return AppColors.amber;
    return AppColors.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    final connected = phase == BlePhase.connected;
    final pct = percent;
    final c = socColor(pct);
    // Tốc độ chỉ có ý nghĩa khi đang kết nối; mất kết nối → "--".
    final shownSpeed = connected ? speedKmh : null;

    final warnings = <String>[
      if (isSideStandDown) 'Chân chống đang hạ',
      if (errorCode != 0) 'Xe báo mã lỗi $errorCode — xem Trung tâm chẩn đoán',
    ];

    final pills = <Widget>[
      if (isLocked)
        const StatusPill(label: 'Đã khóa', color: AppColors.red, icon: Icons.lock_rounded)
      else if (isBikeOn)
        const StatusPill(label: 'Xe sẵn sàng', color: AppColors.tertiary, pulse: true),
      if (isCharging)
        const StatusPill(label: 'Đang sạc', color: AppColors.tertiary, icon: Icons.bolt_rounded),
      if (drivingModeShort != null && connected && isBikeOn)
        StatusPill(label: 'Chế độ $drivingModeShort', color: AppColors.primaryFill),
    ];

    return GlassCard(
      hero: true,
      padding: EdgeInsets.zero,
      accent: warnings.isNotEmpty ? AppColors.amber : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Huy hiệu trạng thái (chỉ hiện khi có dữ liệu tương ứng) ─────
          if (pills.isNotEmpty || isFindingBike)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ...pills,
                  if (isFindingBike)
                    InkWell(
                      onTap: onStopFind,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.redSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.red),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.volume_off_rounded, size: 15, color: AppColors.red),
                            const SizedBox(width: 6),
                            Text('Đang hú còi · bấm để tắt',
                                style: AppTypography.labelMd(color: AppColors.redText)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Ảnh xe (trái) + tốc độ (phải) ──────────────────────────────
          SizedBox(
            height: 168,
            child: Row(
              children: [
                const Expanded(
                  flex: 11,
                  child: Padding(
                    padding: EdgeInsets.only(left: 8, top: 4, bottom: 4),
                    child: BikeImage(),
                  ),
                ),
                Expanded(
                  flex: 9,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, left: 4),
                    child: Semantics(
                      label: shownSpeed == null
                          ? 'Tốc độ hiện tại: chưa có dữ liệu'
                          : 'Tốc độ hiện tại: ${shownSpeed.round()} ki-lô-mét trên giờ',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('TỐC ĐỘ',
                              style: AppTypography.labelSm(color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: AnimatedMetric(
                              value: shownSpeed,
                              unit: 'km/h',
                              valueSize: 54,
                              align: CrossAxisAlignment.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Năng lượng: SOC lớn + quãng đường ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedMetric(
                      value: pct?.toDouble(),
                      unit: '%',
                      label: 'Mức pin (SOC)',
                      valueSize: 44,
                      color: pct == null ? null : AppColors.readable(c),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: AnimatedMetric(
                          value: kmLeft?.toDouble(),
                          unit: 'km',
                          label: 'Quãng đường còn lại',
                          valueSize: 28,
                          align: CrossAxisAlignment.end,
                        ),
                      ),
                      if (kmEstimated && kmLeft != null) ...[
                        const SizedBox(height: 4),
                        const FreshnessBadge(freshness: DataFreshness.estimated),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _EnergyBar(percent: pct, color: c, charging: isCharging),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TickBuilder(
              builder: (context, now) {
                final fresh = connected
                    ? freshnessFromTimestamp(lastTelemetryAt, now: now)
                    : (lastTelemetryAt == null ? DataFreshness.none : DataFreshness.stale);
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        isCharging
                            ? 'Đang sạc${chargePowerW != null && chargePowerW! > 0 ? ' · ${chargePowerW!.round()} W' : ''}'
                            : statusText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm(color: AppColors.textDim),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FreshnessBadge(
                        freshness: fresh,
                        detail: lastTelemetryAt == null ? null : formatAge(lastTelemetryAt, now: now),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Cảnh báo xe ───────────────────────────────────────────────
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.amberSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.amberSoftBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final w in warnings)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.amberText),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(w,
                                  style: AppTypography.labelLg(color: AppColors.amberText)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Thanh năng lượng có hiệu ứng chạy khi đang sạc.
class _EnergyBar extends StatefulWidget {
  final int? percent;
  final Color color;
  final bool charging;
  const _EnergyBar({required this.percent, required this.color, required this.charging});

  @override
  State<_EnergyBar> createState() => _EnergyBarState();
}

class _EnergyBarState extends State<_EnergyBar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.charging) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _EnergyBar old) {
    super.didUpdateWidget(old);
    if (widget.charging && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.charging && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frac = ((widget.percent ?? 0) / 100.0).clamp(0.0, 1.0);
    return Semantics(
      label: widget.percent == null ? 'Chưa có mức pin' : 'Mức pin ${widget.percent}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          height: 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.surfaceContainerHigh),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: frac),
                duration: AppMotion.slow,
                curve: AppMotion.curve,
                builder: (_, f, __) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: f,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, __) {
                      final base = widget.color;
                      final shift = widget.charging ? _ctrl.value : 0.0;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1 + shift * 2, 0),
                            end: Alignment(1 + shift * 2, 0),
                            colors: [
                              base.withValues(alpha: 0.65),
                              base,
                              base.withValues(alpha: 0.65),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
