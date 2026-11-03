// Khối thu gọn cho Trang chủ: tiêu đề + mũi tên, nội dung mở/đóng mượt.
// Chỉ trình bày — nội dung bên trong (widget con) giữ nguyên logic cũ.
// Khi đóng, widget con KHÔNG được dựng nên không tốn tài nguyên.

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';

class OverviewCollapsible extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint; // dòng giải thích ngắn khi đang đóng
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  const OverviewCollapsible({
    super.key,
    required this.icon,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.child,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          label: '$title, ${open ? 'đang mở' : 'đang đóng'}',
          excludeSemantics: true,
          child: GlassCard(
            onTap: onToggle,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, size: AppSizes.iconMd, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.labelLg()),
                      if (hint != null && !open)
                        Text(hint!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm()),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: AppMotion.normal,
                  child: Icon(Icons.expand_more_rounded,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
