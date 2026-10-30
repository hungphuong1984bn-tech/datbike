// AnimatedMetric — số liệu có hiệu ứng cập nhật ngắn (đếm mượt giữa hai giá trị).
// [value] == null → hiện "--" (chưa có dữ liệu thật), KHÔNG bịa số.

import 'package:flutter/material.dart';

import '../app_theme.dart';

class AnimatedMetric extends StatelessWidget {
  final double? value;
  final int decimals;
  final String unit; // "km/h", "V", "A", "W", "%", "kWh"...
  final String? label; // nhãn tiếng Việt phía trên
  final double valueSize;
  final Color? color;
  final CrossAxisAlignment align;

  const AnimatedMetric({
    super.key,
    required this.value,
    this.decimals = 0,
    this.unit = '',
    this.label,
    this.valueSize = 28,
    this.color,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    final v = value;
    final unitStyle = AppTypography.labelMd(color: AppColors.textSecondary);
    final numStyle = AppTypography.evWide(
      fontSize: valueSize,
      color: c,
      letterSpacing: -0.5,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    final Widget number = v == null
        ? Text('--', style: numStyle.copyWith(color: AppColors.textMuted))
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(end: v),
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            builder: (_, shown, __) =>
                Text(shown.toStringAsFixed(decimals), style: numStyle),
          );

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(label!, style: AppTypography.labelMd(color: AppColors.textSecondary)),
        if (label != null) const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            number,
            if (unit.isNotEmpty && v != null) ...[
              const SizedBox(width: 4),
              Text(unit, style: unitStyle),
            ],
          ],
        ),
      ],
    );
  }
}
