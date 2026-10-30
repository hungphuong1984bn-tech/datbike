// Giới thiệu THBIKE — thương hiệu, nhà phát triển, phiên bản và danh mục chức năng.
// Chỉ hiển thị thông tin tĩnh của bản phát hành; không đụng tới BLE hay logic pin/sạc.

import 'package:flutter/material.dart';

import '../../core/brand/app_info.dart';
import '../../ui/app_theme.dart';
import '../../ui/brand_logo.dart';
import '../../ui/ds/ds.dart';
import 'feature_catalog.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static Color _statusColor(FeatureStatus s) {
    switch (s) {
      case FeatureStatus.done:
        return AppColors.mint;
      case FeatureStatus.limited:
        return AppColors.cyan;
      case FeatureStatus.inDev:
        return AppColors.amber;
      case FeatureStatus.unsupported:
        return AppColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DsScaffold(
      title: 'Giới thiệu $kAppName',
      subtitle: kAppTagline,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH, AppSpacing.md, AppSpacing.pageH, AppSpacing.huge),
        children: [
          _hero(),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Thông tin ứng dụng'),
          _infoCard([
            _kv(Icons.two_wheeler_rounded, 'Tên ứng dụng', kAppName),
            _kv(Icons.person_rounded, 'Nhà phát triển', kDeveloperName),
            _kv(Icons.info_outline_rounded, 'Phiên bản', kAppVersion),
            _kv(Icons.build_circle_outlined, 'Build Number', '$kAppBuildNumber'),
            _kv(Icons.phone_android_rounded, 'Nền tảng', appPlatformName),
            _kv(Icons.event_rounded, 'Ngày cập nhật', appReleaseDateVi),
            _kv(Icons.copyright_rounded, 'Bản quyền', kCopyright),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Chức năng của $kAppName'),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Danh mục dưới đây được đối chiếu với mã nguồn. Ứng dụng chỉ hiển thị thông số '
              'mà xe/BMS thực sự cung cấp và không tạo dữ liệu giả.',
              style: AppTypography.bodySm(),
            ),
          ),
          _legend(),
          const SizedBox(height: AppSpacing.md),
          for (final g in kFeatureCatalog) ...[
            _group(g),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  Widget _hero() {
    return GlassCard(
      hero: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            const ThBikeLogo(size: 76),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kAppName,
                      style: AppTypography.evWide(fontSize: 26, letterSpacing: 1.0)),
                  const SizedBox(height: 2),
                  Text(kAppTagline, style: AppTypography.bodyMd()),
                  const SizedBox(height: 6),
                  Text('Phiên bản $kAppVersion (build $kAppBuildNumber)',
                      style: AppTypography.labelMd(color: AppColors.accentDim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
        child: Text(t.toUpperCase(),
            style: AppTypography.labelSm(color: AppColors.textSecondary)
                .copyWith(letterSpacing: 0.8)),
      );

  Widget _infoCard(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(Divider(height: 1, color: AppColors.panelBorder));
      out.add(rows[i]);
    }
    return GlassCard(padding: EdgeInsets.zero, child: Column(children: out));
  }

  Widget _kv(IconData icon, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 4,
              child: Text(k, style: AppTypography.bodySm()),
            ),
            Expanded(
              flex: 6,
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: AppTypography.bodyMd(color: AppColors.textPrimary)),
            ),
          ],
        ),
      );

  Widget _legend() => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [for (final s in FeatureStatus.values) _chip(s)],
      );

  Widget _chip(FeatureStatus s) {
    final c = _statusColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(s.label, style: AppTypography.labelSm(color: c)),
    );
  }

  Widget _group(FeatureGroup g) {
    final rows = <Widget>[];
    for (var i = 0; i < g.items.length; i++) {
      final it = g.items[i];
      if (i > 0) rows.add(Divider(height: 1, color: AppColors.panelBorder));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(it.title, style: AppTypography.bodyMd(color: AppColors.textPrimary)),
            if (it.note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(it.note, style: AppTypography.bodySm()),
            ],
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: _chip(it.status)),
          ],
        ),
      ));
    }
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              children: [
                Icon(g.icon, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('${g.code}. ${g.title}',
                      style: AppTypography.headlineSm(color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.panelBorder),
          ...rows,
        ],
      ),
    );
  }
}
