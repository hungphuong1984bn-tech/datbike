// Bảng 5 cấp độ Regen theo mockup: cột năng lượng tăng dần · 5 nút tròn ·
// trạng thái "xe xác nhận" · giải thích từng cấp · nút Áp dụng.
//
// TRẠNG THÁI KHÓA (hiện tại): giao thức Regen độc lập CHƯA xác minh
// (RegenProtocolSpec.verified = false) → 5 nút hiển thị nhưng KHÔNG bấm chọn được,
// không có mức nào được tô sáng, nút Áp dụng bị vô hiệu. Không bao giờ hiện "đã chọn"
// hay "thành công" khi xe chưa đọc lại xác nhận.
//
// KHI MỞ KHÓA (spec.verified = true): nút chọn mức → "Áp dụng" có hộp thoại xác nhận →
// RegenController.apply() (cổng an toàn + ghi + ĐỌC LẠI + so khớp). Widget này chỉ
// trình bày và gọi controller; không chứa logic giao tiếp xe.
//
// Mô tả từng mức là QUY ƯỚC HIỂN THỊ (1 nhẹ nhất → 5 mạnh nhất), chưa đối chiếu với xe.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/regen/regen_controller.dart';
import '../../core/regen/regen_protocol.dart' show RegenState, RegenSyncStatus;
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart' show StatusPill;

const _labels = ['ECO', 'LIGHT', 'NORMAL', 'STRONG', 'MAX'];
const _descriptions = [
  'Nhẹ nhất — êm ái, ít cảm giác giảm tốc khi nhả ga.',
  'Nhẹ — thu hồi vừa phải khi nhả ga.',
  'Cân bằng giữa êm ái và thu hồi năng lượng.',
  'Mạnh — giảm tốc rõ khi nhả ga, thu hồi nhiều hơn.',
  'Mạnh nhất — giảm tốc nhiều nhất, cần làm quen.',
];
const _orange = Color(0xFFFF7A1A);

/// Màu theo cấp: xanh → vàng → cam.
Color regenLevelColor(int i) {
  final t = (i / 4).clamp(0.0, 1.0);
  return t < 0.5
      ? Color.lerp(AppColors.tertiary, AppColors.amber, t * 2)!
      : Color.lerp(AppColors.amber, _orange, (t - 0.5) * 2)!;
}

class RegenLevelPanel extends ConsumerWidget {
  const RegenLevelPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regen = ref.watch(regenProvider);
    final spec = ref.watch(regenSpecProvider);
    final unlocked = regen.status != RegenSyncStatus.unsupported;
    final busy = regen.status == RegenSyncStatus.writing ||
        regen.status == RegenSyncStatus.verifying;

    final confirmed = unlocked ? regen.currentIndex : null;
    final selected = unlocked ? regen.selectedIndex : null;
    final highlight = confirmed ?? selected; // cột sáng đến mức này

    final reason = regen.message ??
        'Đã khóa: giao thức Regen độc lập của xe chưa được xác minh.';

    return GlassCard(
      key: const Key('regen_level_selector'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                size: 18,
                color: unlocked ? AppColors.greenText : AppColors.amberText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('5 cấp độ phanh tái sinh',
                    style: AppTypography.labelLg()),
              ),
              if (!unlocked)
                StatusPill(label: 'Đã khóa', color: AppColors.amber),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Bars(highlight: highlight, dim: !unlocked),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(builder: (context, c) {
            const gap = 6.0;
            final d = ((c.maxWidth - gap * 4) / 5).clamp(40.0, 54.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 5; i++)
                  _LevelCircle(
                    key: Key('regen_level_btn_$i'),
                    index: i,
                    size: d,
                    enabled: unlocked && !busy && spec.levelByIndex(i) != null,
                    selected: selected == i,
                    confirmed: confirmed == i,
                    onTap: () {
                      if (!unlocked) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(reason)));
                        return;
                      }
                      ref.read(regenProvider.notifier).select(i);
                    },
                  ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.md),
          _StatusLine(
            unlocked: unlocked,
            confirmed: confirmed,
            selected: selected,
          ),
          if (busy) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(minHeight: 3),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            unlocked
                ? (regen.message ?? 'Chọn mức rồi gửi xuống xe để đọc lại xác nhận.')
                : reason,
            key: const Key('regen_level_lock_reason'),
            style: AppTypography.bodySm(
              color: unlocked ? AppColors.textSecondary : AppColors.amberText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ApplyRow(
            unlocked: unlocked,
            busy: busy,
            regen: regen,
            onApply: () => _confirmAndApply(context, ref, regen.selectedIndex!),
            onRefresh: () => ref.read(regenProvider.notifier).refresh(),
          ),
          const Divider(height: AppSpacing.xxl),
          Text('Ý nghĩa từng cấp', style: AppTypography.labelMd(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            'Quy ước hiển thị: mức 1 nhẹ nhất, mức 5 mạnh nhất. Chưa đối chiếu với giá trị trên xe.',
            style: AppTypography.labelSm(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6, right: 8),
                    decoration: BoxDecoration(
                      color: regenLevelColor(i),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${i + 1} · ${_labels[i]}  ',
                          style: AppTypography.labelMd(color: AppColors.textPrimary),
                        ),
                        TextSpan(
                          text: _descriptions[i],
                          style: AppTypography.bodySm(),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndApply(
      BuildContext context, WidgetRef ref, int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Áp dụng mức Regen?'),
        content: Text(
          'Gửi mức ${index + 1} – ${_labels[index]} xuống xe. '
          'Chỉ được coi là thành công khi xe đọc lại đúng mức này. '
          'Chỉ thực hiện khi xe đứng yên.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Áp dụng')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(regenProvider.notifier).apply();
    }
  }
}

/// 5 cột tăng dần xanh → cam. Khóa/chưa biết mức → mờ hết, KHÔNG tô mức nào.
class _Bars extends StatelessWidget {
  final int? highlight;
  final bool dim;
  const _Bars({required this.highlight, required this.dim});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 84,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.normal,
                  height: 24.0 + i * 15,
                  decoration: BoxDecoration(
                    color: regenLevelColor(i).withValues(
                      alpha: (!dim && highlight != null && i <= highlight!) ? 1.0 : 0.28,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelCircle extends StatelessWidget {
  final int index;
  final double size;
  final bool enabled;
  final bool selected;
  final bool confirmed;
  final VoidCallback onTap;

  const _LevelCircle({
    super.key,
    required this.index,
    required this.size,
    required this.enabled,
    required this.selected,
    required this.confirmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = regenLevelColor(index);
    final active = confirmed || selected;
    final fg = !enabled && !active
        ? AppColors.textMuted
        : (active ? AppColors.readable(c) : AppColors.textPrimary);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: 'Mức ${index + 1}, ${_labels[index]}'
          '${confirmed ? ', xe đã xác nhận' : ''}'
          '${enabled ? '' : ', đang khóa'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap, // luôn bắt chạm: khóa → báo lý do, không âm thầm bỏ qua
        child: SizedBox(
          width: size,
          child: Column(
            children: [
              AnimatedContainer(
                duration: AppMotion.normal,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? c.withValues(alpha: 0.18)
                      : AppColors.surfaceContainer,
                  border: Border.all(
                    color: active ? c : AppColors.panelBorder,
                    width: active ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: confirmed
                    ? Icon(Icons.check_rounded, color: fg, size: size * 0.5)
                    : Text('${index + 1}',
                        style: AppTypography.evWide(fontSize: size * 0.42, color: fg)),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[index],
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: AppTypography.labelSm(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool unlocked;
  final int? confirmed;
  final int? selected;
  const _StatusLine({
    required this.unlocked,
    required this.confirmed,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color tone;
    final IconData icon;
    if (!unlocked) {
      text = 'Mức trên xe: chưa đọc được';
      tone = AppColors.amber;
      icon = Icons.help_outline_rounded;
    } else if (confirmed != null) {
      text = 'Xe xác nhận: Mức ${confirmed! + 1} – ${_labels[confirmed!]}';
      tone = AppColors.tertiary;
      icon = Icons.verified_rounded;
    } else {
      text = 'Mức trên xe: chưa đọc từ xe';
      tone = AppColors.textSecondary;
      icon = Icons.help_outline_rounded;
    }
    final pendingSel =
        unlocked && selected != null && selected != confirmed ? selected : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.readable(tone)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    key: const Key('regen_current_status'),
                    style: AppTypography.labelLg(color: AppColors.readable(tone))),
              ),
            ],
          ),
          if (pendingSel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 26),
              child: Text(
                'Đã chọn: Mức ${pendingSel + 1} – ${_labels[pendingSel]} (chưa gửi / chưa xác nhận)',
                style: AppTypography.labelSm(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplyRow extends StatelessWidget {
  final bool unlocked;
  final bool busy;
  final RegenState regen;
  final VoidCallback onApply;
  final VoidCallback onRefresh;

  const _ApplyRow({
    required this.unlocked,
    required this.busy,
    required this.regen,
    required this.onApply,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (!unlocked) {
      // Khác key với nút thật để test "không có nút điều khiển" vẫn đúng khi khóa.
      return SizedBox(
        width: double.infinity,
        height: AppSizes.minTap,
        child: FilledButton.icon(
          key: const Key('regen_apply_locked'),
          onPressed: null,
          icon: const Icon(Icons.lock_outline_rounded),
          label: const Text('Áp dụng · đã khóa'),
        ),
      );
    }
    final canApply = !busy &&
        regen.selectedIndex != null &&
        regen.selectedIndex != regen.currentIndex &&
        regen.status != RegenSyncStatus.synced;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: AppSizes.minTap,
          child: FilledButton(
            key: const Key('regen_apply'),
            onPressed: canApply ? onApply : null,
            child: Text(busy ? 'Đang xử lý…' : 'Áp dụng'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton.icon(
          key: const Key('regen_refresh'),
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Đọc lại từ xe'),
        ),
      ],
    );
  }
}
