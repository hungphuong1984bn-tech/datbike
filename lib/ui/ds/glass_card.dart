// GlassCard — thẻ nhiều lớp dùng chung: nền bán trong suốt + viền sáng + bóng.
// Mặc định KHÔNG làm mờ nền (BackdropFilter tốn GPU trên máy yếu); bật [blur]
// chỉ cho vài thẻ nổi bật, không dùng trong danh sách cuộn dài.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'ds_tokens.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent; // viền + glow nhẹ theo ngữ nghĩa (vd. cảnh báo)
  final bool hero; // nền gradient nổi bật
  final bool blur;
  final double radius;
  final String? semanticLabel;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.accent,
    this.hero = false,
    this.blur = false,
    this.radius = AppRadius.lg,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final borderColor = accent != null
        ? accent!.withValues(alpha: 0.55)
        : AppColors.panelBorderBright.withValues(alpha: dark ? 0.9 : 1.0);
    final fill = hero
        ? null
        : AppColors.panel.withValues(alpha: dark ? 0.82 : 0.94);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        gradient: hero ? AppGradients.hero : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          ...AppColors.cardShadow,
          if (accent != null) ...AppGlow.soft(accent!, intensity: 0.6),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (blur) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: card,
        ),
      );
    }
    if (semanticLabel != null) {
      card = Semantics(container: true, label: semanticLabel, child: card);
    }
    return card;
  }
}
