// Component dùng chung của hệ thống thiết kế (bổ sung cho widgets.dart).
//
//  • DataFreshness / FreshnessBadge — phân biệt dữ liệu THỰC / CŨ / ƯỚC TÍNH /
//    CHƯA CÓ / DEMO. Không bao giờ để số ước tính hoặc mẫu trông như đo thật.
//  • TickBuilder        — dựng lại một vùng nhỏ mỗi giây (tuổi dữ liệu).
//  • StateView          — loading / empty / error / offline / warning + nút thử lại.
//  • showConfirmDialog  — hộp thoại xác nhận thống nhất.
//  • showAppSnack       — thông báo thành công / cảnh báo / lỗi thống nhất.
//  • ThemeModeSelector  — chọn Hệ thống / Sáng / Tối (lưu bền).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/config/ui_prefs.dart';
import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Độ mới / nguồn gốc dữ liệu
// ─────────────────────────────────────────────────────────────────────────────

enum DataFreshness { live, stale, none, estimated, demo }

extension DataFreshnessX on DataFreshness {
  String get label {
    switch (this) {
      case DataFreshness.live:
        return 'Trực tiếp';
      case DataFreshness.stale:
        return 'Dữ liệu cũ';
      case DataFreshness.none:
        return 'Chưa có dữ liệu';
      case DataFreshness.estimated:
        return 'Ước tính';
      case DataFreshness.demo:
        return 'DEMO';
    }
  }

  IconData get icon {
    switch (this) {
      case DataFreshness.live:
        return Icons.sensors_rounded;
      case DataFreshness.stale:
        return Icons.history_toggle_off_rounded;
      case DataFreshness.none:
        return Icons.do_not_disturb_on_outlined;
      case DataFreshness.estimated:
        return Icons.calculate_outlined;
      case DataFreshness.demo:
        return Icons.science_outlined;
    }
  }

  Color get color {
    switch (this) {
      case DataFreshness.live:
        return AppColors.tertiary;
      case DataFreshness.stale:
        return AppColors.amber;
      case DataFreshness.none:
        return AppColors.textMuted;
      case DataFreshness.estimated:
        return AppColors.accent;
      case DataFreshness.demo:
        return AppColors.red;
    }
  }
}

/// Telemetry "mới" nếu nhận khung trong [liveWithin]; quá hạn → cũ.
DataFreshness freshnessFromTimestamp(
  DateTime? at, {
  DateTime? now,
  Duration liveWithin = const Duration(seconds: 5),
}) {
  if (at == null) return DataFreshness.none;
  final age = (now ?? DateTime.now()).difference(at);
  return age <= liveWithin ? DataFreshness.live : DataFreshness.stale;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// "14:32:05"
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// "vừa xong" · "12 giây trước" · "3 phút trước" · "2 giờ trước".
String formatAge(DateTime? at, {DateTime? now}) {
  if (at == null) return 'chưa có';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inSeconds < 3) return 'vừa xong';
  if (d.inSeconds < 60) return '${d.inSeconds} giây trước';
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
  if (d.inHours < 24) return '${d.inHours} giờ trước';
  return '${d.inDays} ngày trước';
}

/// Huy hiệu nhỏ cho độ mới/nguồn dữ liệu. [detail] ví dụ "14:32:05 · 2 giây trước".
class FreshnessBadge extends StatelessWidget {
  final DataFreshness freshness;
  final String? detail;
  final String? labelOverride;

  const FreshnessBadge({
    super.key,
    required this.freshness,
    this.detail,
    this.labelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final c = freshness.color;
    final fg = AppColors.readable(c);
    final text = detail == null
        ? (labelOverride ?? freshness.label)
        : '${labelOverride ?? freshness.label} · $detail';
    return Semantics(
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: AppColors.isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(freshness.icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dựng lại vùng con mỗi [interval] (mặc định 1 giây) — dùng cho "x giây trước".
/// Chỉ bọc vùng nhỏ để không rebuild cả màn hình; Timer luôn được huỷ khi dispose.
class TickBuilder extends StatefulWidget {
  final Duration interval;
  final Widget Function(BuildContext context, DateTime now) builder;

  const TickBuilder({
    super.key,
    this.interval = const Duration(seconds: 1),
    required this.builder,
  });

  @override
  State<TickBuilder> createState() => _TickBuilderState();
}

class _TickBuilderState extends State<TickBuilder> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

// ─────────────────────────────────────────────────────────────────────────────
// Trạng thái màn hình: loading / empty / error / offline / warning
// ─────────────────────────────────────────────────────────────────────────────

enum StateKind { loading, empty, error, offline, warning }

class StateView extends StatelessWidget {
  final StateKind kind;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  /// true → gọn hơn (dùng trong thẻ/danh sách thay vì chiếm cả màn hình).
  final bool compact;

  const StateView({
    super.key,
    required this.kind,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.compact = false,
  });

  Color get _color {
    switch (kind) {
      case StateKind.loading:
        return AppColors.primary;
      case StateKind.empty:
        return AppColors.textSecondary;
      case StateKind.error:
        return AppColors.error;
      case StateKind.offline:
        return AppColors.amber;
      case StateKind.warning:
        return AppColors.amber;
    }
  }

  IconData get _icon {
    if (icon != null) return icon!;
    switch (kind) {
      case StateKind.loading:
        return Icons.hourglass_top_rounded;
      case StateKind.empty:
        return Icons.inbox_outlined;
      case StateKind.error:
        return Icons.error_outline_rounded;
      case StateKind.offline:
        return Icons.bluetooth_disabled_rounded;
      case StateKind.warning:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    final fg = AppColors.readable(c);
    final badge = kind == StateKind.loading
        ? SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: c),
          )
        : Icon(_icon, size: compact ? 26 : 32, color: fg);

    return Semantics(
      liveRegion: true,
      label: message == null ? title : '$title. $message',
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: compact ? AppSpacing.lg : AppSpacing.huge,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: compact ? 52 : 64,
                  height: compact ? 52 : 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: AppColors.isDark ? 0.16 : 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: badge,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      height: 1.4,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(
                      kind == StateKind.error || kind == StateKind.offline
                          ? Icons.refresh_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                    label: Text(actionLabel!),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, AppSizes.minTap),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog xác nhận & snackbar thống nhất
// ─────────────────────────────────────────────────────────────────────────────

/// Hộp thoại xác nhận chuẩn. Trả về true khi người dùng đồng ý.
/// [destructive] → nút xác nhận màu đỏ (xoá, ngắt kết nối, thao tác không hoàn tác).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Xác nhận',
  String cancelLabel = 'Hủy',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: icon == null
          ? null
          : Icon(icon, size: 30, color: destructive ? AppColors.error : AppColors.primary),
      title: Text(title, textAlign: icon == null ? TextAlign.start : TextAlign.center),
      content: Text(message),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.errorFill : AppColors.primaryFill,
            minimumSize: const Size(96, AppSizes.minTap),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

enum SnackKind { info, success, warning, error }

/// Thông báo nổi thống nhất (thay các SnackBar tự chế rải rác).
void showAppSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final IconData icon;
  final Color color;
  switch (kind) {
    case SnackKind.success:
      icon = Icons.check_circle_rounded;
      color = AppColors.tertiary;
    case SnackKind.warning:
      icon = Icons.warning_amber_rounded;
      color = AppColors.amber;
    case SnackKind.error:
      icon = Icons.error_rounded;
      color = AppColors.red;
    case SnackKind.info:
      icon = Icons.info_rounded;
      color = AppColors.cyan;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      content: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Chọn giao diện Hệ thống / Sáng / Tối
// ─────────────────────────────────────────────────────────────────────────────

class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded, size: 18),
            label: Text('Hệ thống'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_rounded, size: 18),
            label: Text('Sáng'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded, size: 18),
            label: Text('Tối'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minTap),
          foregroundColor: AppColors.textDim,
          selectedForegroundColor: AppColors.primary,
          selectedBackgroundColor: AppColors.primarySoft,
          side: BorderSide(color: AppColors.panelBorderBright),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
