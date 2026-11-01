// Tóm tắt "Trung tâm điều khiển vận hành" trên tab Tổng quan: GRAB · ECE · REGEN.
//
// Grab và ECE có CÔNG TẮC THẬT: gạt → kiểm tra điều kiện (kết nối, xe đứng yên,
// telemetry mới) → hộp thoại xác nhận → gửi → đọc lại từ xe (cùng quy trình với
// Trung tâm điều khiển, xem mode_actions.dart). Mở tab KHÔNG gửi lệnh và KHÔNG tự
// đọc; công tắc chỉ bật khi trạng thái đã được ĐỌC TỪ XE (bấm "Đồng bộ").
// Regen: chỉ giám sát — chưa có kênh ghi Regen nào được xác minh
// (docs/REGEN_VERIFICATION.md), nên KHÔNG có công tắc.
//
// Quy tắc (docs/CONTROL_CENTER.md):
//  • Grab/ECE: chỉ hiện BẬT/TẮT khi trạng thái đã ĐỌC TỪ XE (phase ready/confirmed).
//    Chưa đọc / chưa kết nối / không xác nhận → hiện đúng như vậy, không đoán.
//  • ECE: "giới hạn 60 km/h" chỉ ghi khi cả hai cờ ECE và SpeedLimit đọc lại = 1.
//  • Regen: chỉ giám sát (V × I từ telemetry); KHÔNG có công tắc hay chọn mức.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/control/mode_controller.dart';
import '../../core/control/mode_types.dart';
import '../../core/control/regen_monitor.dart';
import '../control_center/mode_actions.dart';
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';

/// Kết quả diễn giải để vẽ một thẻ chế độ (hàm thuần → dễ kiểm thử).
class ModeSummaryView {
  final String value; // "BẬT" · "TẮT" · "CHƯA ĐỌC"…
  final String caption; // dòng giải thích ngắn
  final Severity tone; // màu: ok = xanh, info = xanh dương, warning, critical
  final bool known; // true khi giá trị BẬT/TẮT là thật từ xe

  const ModeSummaryView(this.value, this.caption, this.tone, {this.known = false});
}

/// Diễn giải [ModeState] cho thẻ tóm tắt. Không bao giờ coi cache là "đang bật".
ModeSummaryView summarizeMode(ModeState s, {String Function(ModeState s)? extraCaption}) {
  switch (s.phase) {
    case ModePhase.unsupported:
    case ModePhase.unverified:
      return const ModeSummaryView('CHƯA HỖ TRỢ', 'Chưa xác minh giao thức', Severity.warning);
    case ModePhase.disconnected:
      return const ModeSummaryView('CHƯA KẾT NỐI', 'Kết nối xe để đọc', Severity.info);
    case ModePhase.unread:
      return const ModeSummaryView('CHƯA ĐỌC', 'Mở để đồng bộ từ xe', Severity.info);
    case ModePhase.sending:
      return const ModeSummaryView('ĐANG GỬI', 'Đang gửi lệnh…', Severity.info);
    case ModePhase.verifying:
      return const ModeSummaryView('ĐANG ĐỌC', 'Đang đọc từ xe…', Severity.info);
    case ModePhase.blocked:
      return const ModeSummaryView('BỊ CHẶN', 'Lệnh chưa được gửi', Severity.warning);
    case ModePhase.notConfirmed:
      return const ModeSummaryView('KHÔNG XÁC NHẬN', 'Xe chưa xác nhận', Severity.critical);
    case ModePhase.confirmed:
    case ModePhase.ready:
      final on = s.on;
      if (on == null) {
        return const ModeSummaryView('GIÁ TRỊ LẠ', 'Không diễn giải được', Severity.warning);
      }
      final base = s.phase == ModePhase.confirmed ? 'Đã xác nhận từ xe' : 'Đã đọc từ xe';
      final extra = extraCaption?.call(s);
      return ModeSummaryView(
        on ? 'BẬT' : 'TẮT',
        extra == null || extra.isEmpty ? base : extra,
        on ? Severity.ok : Severity.info,
        known: true,
      );
  }
}

String _eceCaption(ModeState s) {
  final snap = s.snapshot;
  if (snap == null || s.on != true) return '';
  final eff = const EceModeSpec().limitEffective(snap);
  if (eff == true) return 'Giới hạn đã xác nhận';
  if (eff == false) return 'Giới hạn chưa hiệu lực';
  return '';
}

class OverviewControlSummary extends ConsumerWidget {
  /// Mặc định mở route '/control-center'. Cho phép ghi đè khi kiểm thử.
  final VoidCallback? onOpen;
  const OverviewControlSummary({super.key, this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grab = ref.watch(grabModeProvider);
    final ece = ref.watch(eceModeProvider);
    final phase = ref.watch(bleProvider.select((s) => s.phase));
    final tele = ref.watch(bleProvider.select((s) => s.lastTelemetry));
    final connected = phase == BlePhase.connected;
    final fresh = connected && ref.read(bleProvider.notifier).telemetryFresh;
    final regen = fresh ? regenReadingFrom(tele) : null;

    void open() {
      if (onOpen != null) {
        onOpen!();
      } else {
        Navigator.of(context).pushNamed('/control-center');
      }
    }

    // Công tắc chỉ hoạt động khi ĐÃ biết trạng thái thật từ xe và không bận.
    bool canToggle(ModeState s) =>
        connected &&
        !s.busy &&
        s.on != null &&
        s.phase != ModePhase.unsupported &&
        s.phase != ModePhase.unverified;

    final syncing = grab.busy || ece.busy;

    return Semantics(
      container: true,
      label: 'Trung tâm điều khiển vận hành: Grab, ECE, Regen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Trung tâm điều khiển vận hành',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  // Chỉ ĐỌC từ xe, không ghi.
                  onPressed: (!connected || syncing)
                      ? null
                      : () {
                          ref.read(grabModeProvider.notifier).sync();
                          ref.read(eceModeProvider.notifier).sync();
                        },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppSizes.minTap, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Đồng bộ'),
                ),
                TextButton(
                  onPressed: open,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppSizes.minTap, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Mở'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                _ModeRow(
                  keyPrefix: 'home_grab',
                  icon: Icons.inventory_2_rounded,
                  title: 'GRAB',
                  subtitle: 'Vận hành êm, chở tải nặng',
                  view: summarizeMode(grab),
                  isOn: grab.on == true,
                  onChanged: canToggle(grab) ? (v) => toggleGrabMode(context, ref, v) : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _ModeRow(
                  keyPrefix: 'home_ece',
                  icon: Icons.speed_rounded,
                  title: 'ECE',
                  subtitle: 'Giới hạn tốc độ',
                  view: summarizeMode(ece, extraCaption: _eceCaption),
                  isOn: ece.on == true,
                  onChanged: canToggle(ece) ? (v) => toggleEceMode(context, ref, v) : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _RegenRow(powerKw: regen?.powerKw, connected: connected),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gạt công tắc sẽ hỏi xác nhận, chỉ gửi khi xe đứng yên và đọc lại từ xe để xác nhận. '
            'Bấm "Đồng bộ" để đọc trạng thái trước.',
            style: AppTypography.bodySm(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

Color _toneColor(Severity s) {
  switch (s) {
    case Severity.ok:
      return AppColors.tertiary;
    case Severity.info:
      return AppColors.textSecondary;
    case Severity.warning:
      return AppColors.amber;
    case Severity.critical:
      return AppColors.red;
  }
}

class _ModeRow extends StatelessWidget {
  final String keyPrefix;
  final IconData icon;
  final String title;
  final String subtitle;
  final ModeSummaryView view;
  final bool isOn;
  final ValueChanged<bool>? onChanged;

  const _ModeRow({
    required this.keyPrefix,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.view,
    required this.isOn,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _toneColor(view.tone);
    final fg = AppColors.readable(tone);
    return Semantics(
      container: true,
      label: '$title: ${view.value}. ${view.caption}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: AppColors.isDark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone.withValues(alpha: view.known ? 0.45 : 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: AppTypography.labelLg(color: AppColors.textPrimary)
                              .copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(view.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMd(color: fg)
                                .copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSm(color: AppColors.textSecondary)),
                  Text(view.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSm(color: AppColors.textMuted)),
                ],
              ),
            ),
            Semantics(
              label: 'Công tắc $title',
              child: Switch.adaptive(
                key: Key('${keyPrefix}_switch'),
                value: isOn,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegenRow extends StatelessWidget {
  final double? powerKw;
  final bool connected;
  const _RegenRow({required this.powerKw, required this.connected});

  @override
  Widget build(BuildContext context) {
    final p = powerKw;
    final value = p == null ? '--' : '${p.toStringAsFixed(2)} kW';
    return Semantics(
      container: true,
      label: 'Regen, chỉ giám sát: ${p == null ? 'chưa có dữ liệu' : '$value, tính từ điện áp nhân dòng pha'}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.panelSecondary.withValues(alpha: AppColors.isDark ? 0.6 : 0.8),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.panelBorderBright),
        ),
        child: Row(
          children: [
            Icon(Icons.battery_charging_full_rounded, size: 22, color: AppColors.greenText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('REGEN',
                          style: AppTypography.labelLg(color: AppColors.textPrimary)
                              .copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Text(value,
                          style: AppTypography.labelMd(
                                  color: p == null ? AppColors.textMuted : AppColors.textPrimary)
                              .copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Text('Phanh tái sinh',
                      style: AppTypography.labelSm(color: AppColors.textSecondary)),
                  Text(
                    p == null
                        ? (connected ? 'Chưa có dữ liệu mới' : 'Chưa kết nối')
                        : 'Chỉ giám sát (V × I) · chưa có kênh điều khiển được xác minh',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
