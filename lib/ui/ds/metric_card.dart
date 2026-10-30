// MetricCard — ô số liệu nhỏ dùng chung: biểu tượng + nhãn + giá trị (widget bất kỳ).

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'glass_card.dart';

class MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  final Color? accent;

  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: accent,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMd(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
