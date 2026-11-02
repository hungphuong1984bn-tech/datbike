// Trạng thái "sống" dùng chung cho mọi màn hình đọc dữ liệu từ xe.
//
//  • resolveLiveLevel   — hàm thuần: (pha BLE, thời điểm khung cuối, now) → mức độ.
//  • LiveStateBanner    — dải trạng thái đầu trang: Chưa/mất kết nối · Đang kết nối ·
//                         Đang chờ dữ liệu · Dữ liệu cũ. Ẩn hẳn khi dữ liệu còn mới.
//  • SkeletonBlock/Card — khung chờ nhấp nháy nhẹ (tắt khi người dùng bật "giảm chuyển động").
//  • BottomActionBar    — thanh thao tác neo đáy (vùng ngón cái) cho các màn hình phụ.
//
// Chỉ ĐỌC trạng thái BLE (bleProvider); không gửi lệnh, không đổi luồng kết nối.
// Không bao giờ bịa số: banner chỉ nói sự thật về độ mới của dữ liệu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ble/ble_controller.dart' show BlePhase, bleProvider;
import '../app_theme.dart';
import '../components.dart';

/// Mức độ "sống" của dữ liệu xe.
enum LiveLevel {
  /// Đang nhận khung mới (≤ [liveWithin]).
  live,

  /// Đã kết nối nhưng chưa nhận khung nào.
  waiting,

  /// Đã kết nối nhưng khung cuối quá hạn.
  stale,

  /// Đang quét / kết nối / kết nối lại.
  connecting,

  /// Chưa kết nối hoặc đã mất kết nối.
  disconnected,
}

/// Hàm thuần để dễ kiểm thử. Ưu tiên pha kết nối trước, rồi mới xét độ mới.
LiveLevel resolveLiveLevel({
  required BlePhase phase,
  required DateTime? lastTelemetryAt,
  required DateTime now,
  Duration liveWithin = const Duration(seconds: 5),
}) {
  switch (phase) {
    case BlePhase.idle:
    case BlePhase.disconnected:
      return LiveLevel.disconnected;
    case BlePhase.scanning:
    case BlePhase.connecting:
    case BlePhase.reconnecting:
      return LiveLevel.connecting;
    case BlePhase.connected:
      if (lastTelemetryAt == null) return LiveLevel.waiting;
      return now.difference(lastTelemetryAt) <= liveWithin
          ? LiveLevel.live
          : LiveLevel.stale;
  }
}

class LiveStateBanner extends ConsumerWidget {
  /// Khoảng cách quanh banner (mặc định khớp lề trang).
  final EdgeInsetsGeometry margin;

  /// true → hiện cả khi dữ liệu còn mới (dạng "Trực tiếp"). Mặc định ẩn để đỡ nhồi.
  final bool showWhenLive;

  /// Tuỳ chỉnh hành động "Kết nối". Mặc định mở màn quét xe (/scan).
  final VoidCallback? onConnect;

  const LiveStateBanner({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.pageH,
      AppSpacing.sm,
      AppSpacing.pageH,
      AppSpacing.sm,
    ),
    this.showWhenLive = false,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(bleProvider.select((s) => s.phase));
    // Rebuild khi có khung mới (đổi tham chiếu telemetry); độ cũ do TickBuilder lo.
    ref.watch(bleProvider.select((s) => s.lastTelemetry));
    final lastAt = ref.read(bleProvider.notifier).lastTelemetryAt;

    return TickBuilder(
      builder: (context, now) {
        final level = resolveLiveLevel(
          phase: phase,
          lastTelemetryAt: lastAt,
          now: now,
        );
        final visible = level != LiveLevel.live || showWhenLive;
        return AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: visible
              ? Padding(
                  padding: margin,
                  child: _LiveStrip(
                    level: level,
                    phase: phase,
                    lastAt: lastAt,
                    now: now,
                    onConnect: onConnect ??
                        () => Navigator.of(context).pushNamed('/scan'),
                  ),
                )
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}

class _LiveStrip extends StatelessWidget {
  final LiveLevel level;
  final BlePhase phase;
  final DateTime? lastAt;
  final DateTime now;
  final VoidCallback onConnect;

  const _LiveStrip({
    required this.level,
    required this.phase,
    required this.lastAt,
    required this.now,
    required this.onConnect,
  });

  Color get _color {
    switch (level) {
      case LiveLevel.live:
        return AppColors.tertiary;
      case LiveLevel.waiting:
      case LiveLevel.connecting:
      case LiveLevel.stale:
        return AppColors.amber;
      case LiveLevel.disconnected:
        return AppColors.red;
    }
  }

  IconData get _icon {
    switch (level) {
      case LiveLevel.live:
        return Icons.sensors_rounded;
      case LiveLevel.waiting:
        return Icons.hourglass_top_rounded;
      case LiveLevel.stale:
        return Icons.history_toggle_off_rounded;
      case LiveLevel.connecting:
        return Icons.bluetooth_searching_rounded;
      case LiveLevel.disconnected:
        return Icons.link_off_rounded;
    }
  }

  String get _title {
    switch (level) {
      case LiveLevel.live:
        return 'Dữ liệu trực tiếp';
      case LiveLevel.waiting:
        return 'Đang chờ dữ liệu từ xe…';
      case LiveLevel.stale:
        return 'Dữ liệu cũ';
      case LiveLevel.connecting:
        return phase == BlePhase.scanning
            ? 'Đang quét tìm xe…'
            : 'Đang kết nối với xe…';
      case LiveLevel.disconnected:
        return phase == BlePhase.idle ? 'Chưa kết nối xe' : 'Mất kết nối với xe';
    }
  }

  String get _message {
    final at = lastAt;
    final last = at == null
        ? null
        : 'Lần cuối nhận ${formatClock(at)} · ${formatAge(at, now: now)}';
    switch (level) {
      case LiveLevel.live:
        return last ?? 'Đang nhận khung mới từ xe.';
      case LiveLevel.waiting:
        return 'Đã kết nối, chưa nhận khung nào. Số liệu hiện là "--".';
      case LiveLevel.stale:
        return '${last ?? 'Chưa có mốc thời gian'}. Số liệu bên dưới có thể không còn đúng.';
      case LiveLevel.connecting:
        return last == null
            ? 'Số liệu sẽ hiện ngay khi kết nối xong.'
            : 'Đang hiển thị giá trị cuối. $last.';
      case LiveLevel.disconnected:
        return last == null
            ? 'Kết nối xe để xem số liệu thật.'
            : 'Đang hiển thị giá trị cuối, không phải dữ liệu trực tiếp. $last.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    final fg = AppColors.readable(c);
    final busy = level == LiveLevel.connecting || level == LiveLevel.waiting;
    final canConnect = level == LiveLevel.disconnected;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '$_title. $_message',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: c.withValues(alpha: AppColors.isDark ? 0.14 : 0.09),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.withValues(alpha: 0.38)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: busy
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: fg,
                        ),
                      ),
                    )
                  : Icon(_icon, size: AppSizes.iconMd, color: fg),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _message,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (canConnect) ...[
              const SizedBox(width: AppSpacing.sm),
              // Vùng chạm ≥ 48dp; nằm ở mép phải nhưng banner đặt ở đầu trang nên
              // không cản thao tác một tay ở nửa dưới màn hình.
              TextButton(
                onPressed: onConnect,
                style: TextButton.styleFrom(
                  minimumSize: const Size(72, AppSizes.minTap),
                  foregroundColor: fg,
                ),
                child: const Text('Kết nối'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton (trạng thái đang tải)
// ─────────────────────────────────────────────────────────────────────────────

/// Khối chờ nhấp nháy rất nhẹ. Tự đứng yên khi hệ thống bật "giảm chuyển động".
class SkeletonBlock extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBlock({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.sm,
  });

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surfaceContainerHigh;
    return Semantics(
      label: 'Đang tải',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base.withValues(alpha: 0.45 + 0.35 * _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Thẻ khung chờ: tiêu đề ngắn + [lines] dòng nội dung.
class SkeletonCard extends StatelessWidget {
  final int lines;
  final EdgeInsetsGeometry margin;

  const SkeletonCard({
    super.key,
    this.lines = 3,
    this.margin = const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageH,
      vertical: AppSpacing.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBlock(width: 120, height: 16),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < lines; i++) ...[
              SkeletonBlock(
                // Dòng cuối ngắn hơn cho giống đoạn văn.
                width: i == lines - 1 ? 180 : null,
                height: 12,
              ),
              if (i != lines - 1) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thanh thao tác neo đáy — vùng ngón cái
// ─────────────────────────────────────────────────────────────────────────────

/// Đặt vào `Scaffold.bottomNavigationBar` của màn hình phụ để nút chính luôn
/// nằm trong tầm ngón cái. Tự tránh thanh điều hướng/cử chỉ hệ thống.
class BottomActionBar extends StatelessWidget {
  final Widget child;

  const BottomActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(
          top: BorderSide(
            color: AppColors.isDark
                ? AppColors.panelBorderBright.withValues(alpha: 0.7)
                : AppColors.panelBorder,
          ),
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH,
            AppSpacing.md,
            AppSpacing.pageH,
            AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}
