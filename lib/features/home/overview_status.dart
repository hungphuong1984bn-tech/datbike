// Thẻ trạng thái & lối tắt của màn Tổng quan.
//
// Nguyên tắc dữ liệu: chỉ hiển thị giá trị xe đã gửi thật. Chưa có telemetry
// → "--" + huy hiệu "Chưa có dữ liệu". Mất kết nối → vẫn cho xem giá trị cuối
// nhưng gắn "Dữ liệu cũ" kèm giờ nhận. Không dùng số mẫu.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ble/ble_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/widgets.dart';

String blePhaseLabel(BlePhase p) {
  switch (p) {
    case BlePhase.connected:
      return 'Đã kết nối';
    case BlePhase.connecting:
      return 'Đang kết nối…';
    case BlePhase.reconnecting:
      return 'Đang kết nối lại…';
    case BlePhase.scanning:
      return 'Đang quét xe…';
    case BlePhase.disconnected:
      return 'Mất kết nối';
    case BlePhase.idle:
      return 'Chưa kết nối';
  }
}

Color blePhaseColor(BlePhase p) {
  switch (p) {
    case BlePhase.connected:
      return AppColors.tertiary;
    case BlePhase.connecting:
    case BlePhase.reconnecting:
    case BlePhase.scanning:
      return AppColors.amber;
    case BlePhase.disconnected:
      return AppColors.red;
    case BlePhase.idle:
      return AppColors.textMuted;
  }
}

class OverviewStatusCard extends StatelessWidget {
  final BlePhase phase;
  final DateTime? lastTelemetryAt;
  final int? percent;
  final double? speedKmh;
  final bool isLocked;
  final VoidCallback onConnect;

  const OverviewStatusCard({
    super.key,
    required this.phase,
    required this.lastTelemetryAt,
    required this.percent,
    required this.speedKmh,
    required this.isLocked,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = phase == BlePhase.connected;
    final busy = phase == BlePhase.connecting ||
        phase == BlePhase.reconnecting ||
        phase == BlePhase.scanning;
    final phaseColor = blePhaseColor(phase);

    return TickBuilder(
      builder: (context, now) {
        final fresh = connected
            ? freshnessFromTimestamp(lastTelemetryAt, now: now)
            : (lastTelemetryAt == null ? DataFreshness.none : DataFreshness.stale);
        final hasValues = lastTelemetryAt != null && percent != null;
        final pct = hasValues ? percent! : null;
        final pctVal = pct ?? 100;
        final low = pct != null && pctVal <= 20 && fresh != DataFreshness.stale;
        final stamp = lastTelemetryAt == null
            ? 'Chưa nhận được dữ liệu từ xe'
            : 'Cập nhật ${formatClock(lastTelemetryAt!)} · ${formatAge(lastTelemetryAt, now: now)}';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.panelBorderBright),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: phaseColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      blePhaseLabel(phase),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  FreshnessBadge(freshness: fresh),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Pin',
                      value: pct == null ? '--' : '$pct',
                      unit: '%',
                      color: low ? AppColors.redText : AppColors.textPrimary,
                    ),
                  ),
                  Container(width: 1, height: 40, color: AppColors.panelBorderBright),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _Metric(
                      label: 'Tốc độ gần nhất',
                      value: (!hasValues || speedKmh == null) ? '--' : speedKmh!.toStringAsFixed(0),
                      unit: 'km/h',
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                stamp,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (!connected && !busy) ...[
                const SizedBox(height: AppSpacing.md),
                NoticeBanner(
                  color: AppColors.amber,
                  icon: Icons.bluetooth_disabled_rounded,
                  text: lastTelemetryAt == null
                      ? 'Chưa kết nối xe. Kết nối để xem pin và tốc độ.'
                      : 'Mất kết nối — số liệu trên là giá trị cuối cùng, không còn cập nhật.',
                  trailing: TextButton(onPressed: onConnect, child: const Text('Kết nối')),
                ),
              ],
              if (busy) ...[
                const SizedBox(height: AppSpacing.md),
                NoticeBanner(
                  color: AppColors.cyan,
                  icon: Icons.bluetooth_searching_rounded,
                  text: blePhaseLabel(phase),
                ),
              ],
              if (connected && fresh == DataFreshness.stale) ...[
                const SizedBox(height: AppSpacing.md),
                const NoticeBanner(
                  color: AppColors.amber,
                  icon: Icons.history_toggle_off_rounded,
                  text: 'Đã kết nối nhưng xe chưa gửi dữ liệu mới. Số liệu có thể đã cũ.',
                ),
              ],
              if (low) ...[
                const SizedBox(height: AppSpacing.md),
                NoticeBanner(
                  color: pctVal <= 10 ? AppColors.red : AppColors.amber,
                  icon: Icons.battery_alert_rounded,
                  text: pctVal <= 10
                      ? 'Pin còn $pctVal% — cần sạc ngay.'
                      : 'Pin còn $pctVal% — nên sạc sớm.',
                ),
              ],
              if (connected && isLocked) ...[
                const SizedBox(height: AppSpacing.md),
                const NoticeBanner(
                  color: AppColors.cyan,
                  icon: Icons.lock_rounded,
                  text: 'Xe đang khóa an toàn.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value $unit',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lối tắt tới các chức năng chính (vùng chạm ≥ 64dp, thao tác một tay).
class OverviewShortcuts extends StatelessWidget {
  final VoidCallback onHud;
  final VoidCallback onCharging;
  final VoidCallback onTrips;

  const OverviewShortcuts({
    super.key,
    required this.onHud,
    required this.onCharging,
    required this.onTrips,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Tile(
            icon: Icons.speed_rounded,
            label: 'Đồng hồ lái (HUD)',
            onTap: onHud,
            highlighted: true,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Tile(icon: Icons.bolt_rounded, label: 'Sạc & Năng lượng', onTap: onCharging),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Tile(icon: Icons.route_rounded, label: 'Hành trình', onTap: onTrips),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? AppColors.primary : AppColors.textPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: highlighted ? AppColors.primarySoft : AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: highlighted ? AppColors.primarySoftBorder : AppColors.panelBorderBright,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: fg),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh trạng thái xe gọn cho tab Tổng quan (thay vì thẻ lớn).
///
/// Chỉ hiện chip khi dữ liệu tương ứng THẬT và còn mới:
///  • Luôn có: Bluetooth + độ mới telemetry.
///  • Chỉ khi đã kết nối và telemetry "Trực tiếp": nguồn xe, khóa, chân chống,
///    xi-nhan, đèn pha, mã lỗi, pin yếu.
///  • Mất kết nối / telemetry cũ: hiện cảnh báo thay vì trạng thái cũ.
/// Không tạo cảnh báo khi chưa có dữ liệu hoặc chưa đạt điều kiện.
class OverviewStatusStrip extends StatelessWidget {
  final BlePhase phase;
  final DateTime? lastTelemetryAt;
  final int? percent;
  final bool isBikeOn;
  final bool isLocked;
  final bool isSideStandDown;
  final bool leftIndicator;
  final bool rightIndicator;
  final bool headlight;
  final int errorCode;
  final VoidCallback onConnect;

  const OverviewStatusStrip({
    super.key,
    required this.phase,
    required this.lastTelemetryAt,
    required this.percent,
    required this.isBikeOn,
    required this.isLocked,
    required this.isSideStandDown,
    required this.leftIndicator,
    required this.rightIndicator,
    required this.headlight,
    required this.errorCode,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = phase == BlePhase.connected;
    final busy = phase == BlePhase.connecting ||
        phase == BlePhase.reconnecting ||
        phase == BlePhase.scanning;

    return TickBuilder(
      builder: (context, now) {
        final fresh = connected
            ? freshnessFromTimestamp(lastTelemetryAt, now: now)
            : (lastTelemetryAt == null ? DataFreshness.none : DataFreshness.stale);
        final live = connected && fresh == DataFreshness.live;
        final pct = percent;
        final int? lowPct = (live && pct != null && pct <= 20) ? pct : null;

        final chips = <Widget>[
          _StateChip(
            icon: connected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            label: blePhaseLabel(phase),
            color: blePhaseColor(phase),
          ),
          if (live) ...[
            _StateChip(
              icon: Icons.power_settings_new_rounded,
              label: isBikeOn ? 'Xe đang bật' : 'Xe đang tắt',
              color: isBikeOn ? AppColors.tertiary : AppColors.textMuted,
            ),
            _StateChip(
              icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              label: isLocked ? 'Đã khóa' : 'Đã mở khóa',
              color: isLocked ? AppColors.cyan : AppColors.textMuted,
            ),
            if (isSideStandDown)
              const _StateChip(
                icon: Icons.vertical_align_bottom_rounded,
                label: 'Chân chống hạ',
                color: AppColors.amber,
              ),
            if (leftIndicator)
              const _StateChip(
                icon: Icons.arrow_back_rounded,
                label: 'Xi-nhan trái',
                color: AppColors.amber,
              ),
            if (rightIndicator)
              const _StateChip(
                icon: Icons.arrow_forward_rounded,
                label: 'Xi-nhan phải',
                color: AppColors.amber,
              ),
            if (headlight)
              const _StateChip(
                icon: Icons.light_mode_rounded,
                label: 'Đèn pha',
                color: AppColors.cyan,
              ),
            if (errorCode != 0)
              _StateChip(
                icon: Icons.error_outline_rounded,
                label: 'Mã lỗi $errorCode',
                color: AppColors.red,
              ),
            if (lowPct != null)
              _StateChip(
                icon: Icons.battery_alert_rounded,
                label: lowPct <= 10
                    ? 'Pin còn $lowPct% — sạc ngay'
                    : 'Pin còn $lowPct% — nên sạc',
                color: lowPct <= 10 ? AppColors.red : AppColors.amber,
              ),
          ],
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: SectionTitle('Trạng thái xe')),
                Flexible(
                  child: FreshnessBadge(
                    freshness: fresh,
                    detail: lastTelemetryAt == null
                        ? null
                        : formatAge(lastTelemetryAt, now: now),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            if (!connected && !busy) ...[
              const SizedBox(height: AppSpacing.md),
              NoticeBanner(
                color: AppColors.amber,
                icon: Icons.bluetooth_disabled_rounded,
                text: lastTelemetryAt == null
                    ? 'Chưa kết nối xe. Kết nối để xem pin, tốc độ và điều khiển.'
                    : 'Mất kết nối — số liệu bên dưới là giá trị cuối cùng, không còn cập nhật.',
                trailing: TextButton(onPressed: onConnect, child: const Text('Kết nối')),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: AppSpacing.md),
              NoticeBanner(
                color: AppColors.cyan,
                icon: Icons.bluetooth_searching_rounded,
                text: blePhaseLabel(phase),
              ),
            ],
            if (connected && fresh == DataFreshness.stale) ...[
              const SizedBox(height: AppSpacing.md),
              const NoticeBanner(
                color: AppColors.amber,
                icon: Icons.history_toggle_off_rounded,
                text: 'Đã kết nối nhưng xe chưa gửi dữ liệu mới. Số liệu có thể đã cũ.',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Chip trạng thái nhỏ: biểu tượng + chữ, tô màu theo ngữ nghĩa.
class _StateChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StateChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.readable(color);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppColors.isDark ? 0.14 : 0.09),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMd(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
