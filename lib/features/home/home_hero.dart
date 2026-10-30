// Thẻ "Tổng quan xe" của trang chủ — Design System v3.
//
// Nguyên tắc dữ liệu: chỉ hiển thị giá trị xe đã gửi thật. Giá trị null → "--".
// Không dùng số mẫu. Quãng đường còn lại do app tự ước tính được gắn nhãn "Ước tính".
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
  final String bikeName;

  // Số liệu thật (null = chưa có)
  final int? percent;
  final int? kmLeft;
  final bool kmEstimated;
  final double? speedKmh;
  final double? voltageV;
  final double? powerW;
  final double? bmsTempC;

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
  final VoidCallback onSwitchBike;
  final VoidCallback onHud;
  final VoidCallback onConnect;
  final VoidCallback onStopFind;

  const HomeHeroCard({
    super.key,
    required this.phase,
    required this.lastTelemetryAt,
    required this.bikeName,
    required this.percent,
    required this.kmLeft,
    required this.kmEstimated,
    required this.speedKmh,
    required this.voltageV,
    required this.powerW,
    required this.bmsTempC,
    required this.statusText,
    required this.drivingModeShort,
    required this.isBikeOn,
    required this.isLocked,
    required this.isCharging,
    required this.chargePowerW,
    required this.isSideStandDown,
    required this.errorCode,
    required this.isFindingBike,
    required this.onSwitchBike,
    required this.onHud,
    required this.onConnect,
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

    final warnings = <String>[
      if (isSideStandDown) 'Chân chống đang hạ',
      if (errorCode != 0) 'Xe báo mã lỗi $errorCode — xem Trung tâm chẩn đoán',
    ];

    return GlassCard(
      hero: true,
      padding: EdgeInsets.zero,
      accent: warnings.isNotEmpty ? AppColors.amber : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Đầu thẻ: tên xe · kết nối · HUD ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onSwitchBike,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              bikeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.evWide(fontSize: 18, letterSpacing: -0.3),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.unfold_more_rounded, size: 18, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: connected ? null : onConnect,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: ConnectionBadge(phase: phase),
                ),
                IconButton(
                  tooltip: 'Đồng hồ lái (HUD)',
                  icon: Icon(Icons.speed_rounded, size: 22, color: AppColors.textPrimary),
                  onPressed: onHud,
                ),
              ],
            ),
          ),

          // ── Năng lượng: SOC lớn + quãng đường ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedMetric(
                  value: pct?.toDouble(),
                  unit: '%',
                  label: 'Mức pin (SOC)',
                  valueSize: 54,
                  color: pct == null ? null : AppColors.readable(c),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedMetric(
                      value: kmLeft?.toDouble(),
                      unit: 'km',
                      label: 'Quãng đường còn lại',
                      valueSize: 30,
                      align: CrossAxisAlignment.end,
                    ),
                    if (kmEstimated && kmLeft != null) ...[
                      const SizedBox(height: 4),
                      const FreshnessBadge(freshness: DataFreshness.estimated),
                    ],
                  ],
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm(color: AppColors.textDim),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FreshnessBadge(
                      freshness: fresh,
                      detail: lastTelemetryAt == null ? null : formatAge(lastTelemetryAt, now: now),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Ảnh xe + huy hiệu ─────────────────────────────────────────
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: BikeImage(),
                ),
                if (isBikeOn)
                  const Positioned(
                    top: 8,
                    left: 14,
                    child: StatusPill(label: 'Xe sẵn sàng', color: AppColors.tertiary, pulse: true),
                  ),
                if (isLocked)
                  const Positioned(
                    top: 8,
                    left: 14,
                    child: StatusPill(
                        label: 'Đã khóa', color: AppColors.red, icon: Icons.lock_rounded),
                  ),
                if (drivingModeShort != null && connected)
                  Positioned(
                    top: 8,
                    right: 14,
                    child: StatusPill(
                      label: 'Chế độ $drivingModeShort',
                      color: AppColors.primaryFill,
                    ),
                  ),
                if (isFindingBike)
                  Positioned(
                    bottom: 8,
                    right: 14,
                    child: InkWell(
                      onTap: onStopFind,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                  ),
              ],
            ),
          ),

          // ── Cảnh báo xe ───────────────────────────────────────────────
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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

          // ── Thông số nhanh ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.speed_rounded,
                    label: 'Tốc độ',
                    value: speedKmh,
                    unit: 'km/h',
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    icon: Icons.bolt_rounded,
                    label: 'Công suất',
                    value: powerW,
                    unit: 'W',
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    icon: Icons.device_thermostat_rounded,
                    label: 'Nhiệt độ pin',
                    value: bmsTempC,
                    unit: '°C',
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    icon: Icons.electrical_services_rounded,
                    label: 'Điện áp',
                    value: voltageV,
                    unit: 'V',
                    decimals: 1,
                  ),
                ),
              ],
            ),
          ),
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

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? value;
  final String unit;
  final int decimals;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.decimals = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.panel.withValues(alpha: AppColors.isDark ? 0.55 : 0.8),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedMetric(
                value: value,
                decimals: decimals,
                unit: unit,
                valueSize: 18,
                align: CrossAxisAlignment.center,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSm(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
