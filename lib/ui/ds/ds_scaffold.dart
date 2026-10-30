// DsScaffold + DsSectionHeader — khung trang thống nhất cho mọi trang con:
// nền gradient nhẹ, tiêu đề tiếng Việt, lề ngang chuẩn, không chật chội.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'ds_tokens.dart';

class DsScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body; // thường là ListView/CustomScrollView tự quản lý padding
  final bool showBack;

  const DsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: showBack && canPop,
        centerTitle: false,
        titleSpacing: showBack && canPop ? 0 : AppSpacing.pageH,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppTypography.evWide(fontSize: 20, letterSpacing: -0.3)),
            if (subtitle != null)
              Text(subtitle!, style: AppTypography.labelMd()),
          ],
        ),
        actions: actions,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.page),
        child: SafeArea(top: false, child: body),
      ),
    );
  }
}

class DsSectionHeader extends StatelessWidget {
  final String title;
  final String? hint; // giải thích ngắn bằng tiếng Việt
  final Widget? trailing;

  const DsSectionHeader(this.title, {super.key, this.hint, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, AppSpacing.xl, AppSpacing.pageH, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.labelLg()),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(hint!, style: AppTypography.bodySm()),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
