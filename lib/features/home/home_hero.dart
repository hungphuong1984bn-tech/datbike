// Thẻ "Tổng quan xe" của trang chủ — Design System v3 (Premium EV), bố cục theo mockup.
//
// Bố cục: huy hiệu trạng thái → [vòng SOC | ảnh xe] → tốc độ lớn + ODO →
// hàng Điện áp · Dòng điện · Công suất → thanh Regen → độ mới dữ liệu → cảnh báo.
//
// Nguyên tắc dữ liệu: chỉ hiển thị giá trị xe đã gửi thật. Giá trị null → "--".
// Quãng đường còn lại do app tự ước tính được gắn dấu "≈". Mất kết nối: tốc độ,
// điện áp, dòng, công suất về "--" (không để số cũ trông như đang chạy).
// Dòng điện = dòng pha bộ điều khiển, theo dấu ĐÃ KIỂM CHỨNG (docs/REGEN_VERIFICATION.md):
// dương = nạp ngược (regen), âm = kéo ga. Công suất = V × I giữ nguyên dấu.
// Thanh Regen chỉ phản ánh dòng nạp ĐO ĐƯỢC; mức Regen 1–5 chưa đọc được từ xe
// nên KHÔNG hiển thị mức giả.
// Widget chỉ nhận tham số thuần (không đọc BLE) nên dễ kiểm thử và không ảnh hưởng giao thức.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ble/ble_controller.dart' show BlePhase;
import '../../core/control/regen_monitor.dart';
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

  // Mới (tuỳ chọn, null = chưa có dữ liệu)
  final double? odoKm;
  final RegenReading? reading; // V · I · P thật từ telemetry
  final double? recoveredWh; // năng lượng thu hồi tích lũy từ lúc reset

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
    this.odoKm,
    this.reading,
    this.recoveredWh,
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
    // Số tức thời chỉ có ý nghĩa khi đang kết nối; mất kết nối → "--".
    final shownSpeed = connected ? speedKmh : null;
    final r = connected ? reading : null;

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

          // ── Vòng SOC (trái) + ảnh xe (phải) ─────────────────────────────
          SizedBox(
            height: 172,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 10),
                  child: _SocRing(
                    percent: pct,
                    color: c,
                    kmLeft: kmLeft,
                    kmEstimated: kmEstimated,
                    charging: isCharging,
                  ),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
                    child: BikeImage(),
                  ),
                ),
              ],
            ),
          ),

          // ── Tốc độ lớn (giữa) + ODO (phải) ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(child: SizedBox()),
                Semantics(
                  label: shownSpeed == null
                      ? 'Tốc độ hiện tại: chưa có dữ liệu'
                      : 'Tốc độ hiện tại: ${shownSpeed.round()} ki-lô-mét trên giờ',
                  excludeSemantics: true,
                  child: AnimatedMetric(
                    value: shownSpeed,
                    unit: 'km/h',
                    valueSize: 64,
                    align: CrossAxisAlignment.center,
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: AnimatedMetric(
                        value: connected ? odoKm : null,
                        unit: 'km',
                        label: 'ODO',
                        valueSize: 20,
                        align: CrossAxisAlignment.end,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Điện áp · Dòng điện · Công suất ────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    icon: Icons.bolt_rounded,
                    label: 'Điện áp',
                    value: r?.voltageV,
                    unit: 'V',
                    decimals: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.electric_meter_rounded,
                    label: 'Dòng điện',
                    value: r?.phaseCurrentA,
                    unit: 'A',
                    decimals: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.flash_on_rounded,
                    label: 'Công suất',
                    value: r?.powerKw,
                    unit: 'kW',
                    decimals: 1,
                  ),
                ),
              ],
            ),
          ),

          // ── Thanh Regen (số đo thật, không phải mức cài đặt) ───────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _RegenStrip(
              reading: r,
              recoveredWh: connected ? recoveredWh : null,
            ),
          ),

          // ── Trạng thái + độ mới dữ liệu ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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

/// Vòng SOC: cung gradient theo mức pin, số % lớn và quãng đường còn lại ở giữa.
class _SocRing extends StatelessWidget {
  final int? percent;
  final Color color;
  final int? kmLeft;
  final bool kmEstimated;
  final bool charging;

  const _SocRing({
    required this.percent,
    required this.color,
    required this.kmLeft,
    required this.kmEstimated,
    required this.charging,
  });

  @override
  Widget build(BuildContext context) {
    final frac = ((percent ?? 0) / 100.0).clamp(0.0, 1.0);
    final km = kmLeft == null ? '-- km' : '${kmEstimated ? '≈ ' : ''}$kmLeft km';
    return Semantics(
      label: percent == null
          ? 'Mức pin: chưa có dữ liệu'
          : 'Mức pin $percent phần trăm, quãng đường còn lại ${kmLeft ?? 'chưa rõ'} ki-lô-mét',
      excludeSemantics: true,
      child: SizedBox(
        width: 136,
        height: 136,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: frac),
          duration: AppMotion.slow,
          curve: AppMotion.curve,
          builder: (_, f, __) => CustomPaint(
            painter: _RingPainter(
              fraction: f,
              hasValue: percent != null,
              color: color,
              track: AppColors.surfaceContainerHigh,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (charging)
                    Icon(Icons.bolt_rounded, size: 16, color: AppColors.tertiary),
                  Text(
                    percent == null ? '--' : '$percent%',
                    style: AppTypography.evWide(
                      fontSize: 34,
                      color: percent == null
                          ? AppColors.textMuted
                          : AppColors.readable(color),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(km, style: AppTypography.labelMd(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final bool hasValue;
  final Color color;
  final Color track;

  const _RingPainter({
    required this.fraction,
    required this.hasValue,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 2);
    const start = -math.pi / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, trackPaint);

    if (!hasValue || fraction <= 0) return;
    final sweep = math.pi * 2 * fraction;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: const GradientRotation(start),
        colors: [color, AppColors.cyan, color],
      ).createShader(rect);
    canvas.drawArc(arcRect, start, sweep, false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.fraction != fraction ||
      o.hasValue != hasValue ||
      o.color != color ||
      o.track != track;
}

/// Ô số liệu gọn: biểu tượng · số (có dấu) · đơn vị · nhãn. null → "--".
class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? value;
  final String unit;
  final int decimals;

  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.decimals,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Semantics(
      label: v == null
          ? '$label: chưa có dữ liệu'
          : '$label: ${v.toStringAsFixed(decimals)} $unit',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.panel.withValues(alpha: AppColors.isDark ? 0.55 : 0.8),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: AppColors.isDark
                ? AppColors.panelBorderBright.withValues(alpha: 0.6)
                : AppColors.panelBorder,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: v == null ? AppColors.textMuted : AppColors.cyan),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    v == null ? '--' : v.toStringAsFixed(decimals),
                    style: AppTypography.evWide(
                      fontSize: 20,
                      color: v == null ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                  if (v != null) ...[
                    const SizedBox(width: 3),
                    Text(unit,
                        style: AppTypography.labelMd(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSm(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Thanh Regen: 5 vạch sáng theo dòng nạp ĐO ĐƯỢC (mỗi vạch ≈ 5 A), kèm nhãn trạng thái.
/// Không hiển thị "mức 1–5" vì xe chưa có kênh đọc mức Regen được xác minh.
class _RegenStrip extends StatelessWidget {
  final RegenReading? reading;
  final double? recoveredWh;

  const _RegenStrip({required this.reading, required this.recoveredWh});

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final flow = classifyRegenFlow(r);
    final String text;
    final Color tone;
    var lit = 0;
    if (r == null) {
      text = 'Regen: chưa có dữ liệu';
      tone = AppColors.textMuted;
    } else if (flow == RegenFlow.regen) {
      text = 'Regen: đang thu hồi · ${r.powerKw.toStringAsFixed(1)} kW';
      tone = AppColors.tertiary;
      lit = (r.phaseCurrentA / 5).ceil().clamp(1, 5);
    } else if (flow == RegenFlow.traction) {
      text = 'Regen: đang kéo ga';
      tone = AppColors.amber;
    } else {
      text = 'Regen: chưa thu hồi';
      tone = AppColors.textSecondary;
    }
    final wh = recoveredWh;
    return Semantics(
      label: '$text. Mức Regen cài đặt chưa đọc được từ xe.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.energy_savings_leaf_rounded, size: 20, color: AppColors.readable(tone)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLg(color: AppColors.readable(tone))),
                  Text(
                    (wh != null && wh > 0)
                        ? 'Đã thu hồi ${wh.toStringAsFixed(wh < 10 ? 1 : 0)} Wh · mức cài đặt chưa đọc được'
                        : 'Số đo thật từ xe · mức cài đặt chưa đọc được',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: AnimatedContainer(
                      duration: AppMotion.normal,
                      width: 6,
                      height: 8.0 + i * 4,
                      decoration: BoxDecoration(
                        color: i < lit ? tone : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
