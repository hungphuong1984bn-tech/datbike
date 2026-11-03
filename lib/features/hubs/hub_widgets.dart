// Thành phần dùng chung cho hai trung tâm VEHICLE và CONTROL.
// Chỉ trình bày: không gửi lệnh BLE, không đổi luồng kết nối.

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';

/// Ô số liệu: giá trị null → hiển thị "N/A" (không bao giờ bịa số).
class HubStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value; // null = chưa có dữ liệu
  final String unit;
  final Color? accent;

  const HubStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    return MetricCard(
      icon: icon,
      label: label,
      accent: has ? accent : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              has ? value! : 'N/A',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.evWide(
                fontSize: 22,
                color: has ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
          if (has && unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(unit, style: AppTypography.labelMd(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Lưới 2 cột không cuộn riêng (nằm trong ListView của trang).
class HubGrid extends StatelessWidget {
  final List<Widget> children;
  const HubGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
      child: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      }),
    );
  }
}

/// Dòng điều hướng tới một màn hình thật có sẵn.
class HubLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function() builder;
  final Color? color;

  const HubLink({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.md),
      child: GlassCard(
        semanticLabel: '$title. $subtitle',
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => builder())),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: c, size: AppSizes.iconLg),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelLg()),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm()),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
