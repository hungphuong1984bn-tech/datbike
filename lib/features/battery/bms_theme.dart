// Bộ giao diện "Premium EV Battery Monitoring": nền tối có chiều sâu, khối kính
// (glassmorphism), màu trạng thái và các widget nhỏ dùng chung cho màn hình BMS.
// Theo palette sáng/tối của app (AppColors): Dark giữ nguyên diện mạo Premium cũ,
// Light dùng cùng hệ màu với các màn hình còn lại. Mọi màu là getter nên đổi chế độ
// có hiệu lực ngay (gốc app ép dựng lại cây widget khi đổi giao diện).

import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/battery/cell_model.dart';
import '../../core/battery/cell_protection_engine.dart';
import '../../ui/app_theme.dart';

class Bms {
  Bms._();

  static bool get _dark => AppColors.isDark;

  // Nền
  static Color get bg => _dark ? const Color(0xFF080B11) : AppColors.bg;
  static Color get bgMid => _dark ? const Color(0xFF0D131D) : AppColors.panelSecondary;
  static Color get bgGlow => _dark
      ? const Color(0xFF12223D)
      : Color.alphaBlend(AppColors.electric.withValues(alpha: 0.10), AppColors.bg);

  // Chữ (3 bậc). Dark: textFaint nâng nhẹ để đạt tương phản ≥ 4.5:1 trên nền.
  static Color get text => _dark ? const Color(0xFFEAF0FA) : AppColors.textPrimary;
  static Color get textDim => _dark ? const Color(0xFF8FA0BC) : AppColors.textDim;
  static Color get textFaint => _dark ? const Color(0xFF74839C) : AppColors.textMuted;

  // Nhấn
  static Color get accent => _dark ? const Color(0xFF22D3EE) : AppColors.accent;
  static Color get accent2 => _dark ? const Color(0xFF4F7DFF) : AppColors.primary;

  // Ngữ nghĩa (Light dùng biến thể đậm hơn để đọc được ngoài trời)
  static Color get ok => _dark ? const Color(0xFF22D3A0) : AppColors.greenText;
  static Color get warning => _dark ? const Color(0xFFFBBF24) : AppColors.amberText;
  static Color get critical => _dark ? const Color(0xFFF43F5E) : AppColors.redText;
  static Color get invalid => _dark ? const Color(0xFF64748B) : AppColors.textMuted;
  static Color get estimated => _dark ? const Color(0xFFA78BFA) : const Color(0xFF6D4AD8);

  // Viền / bề mặt
  static Color get border => _dark ? const Color(0x1FFFFFFF) : AppColors.panelBorderBright;
  static Color get glassFill => _dark ? const Color(0x0FFFFFFF) : AppColors.panel;

  /// Lớp phủ nhạt dùng cho vạch lưới, nền ô nhập, thanh nền… (trắng ở Dark, mực ở Light).
  static Color overlay(double a) => _dark
      ? Colors.white.withValues(alpha: a)
      : AppColors.textPrimary.withValues(alpha: (a * 0.75).clamp(0.0, 1.0));

  /// Nền lõm (khung pin): tối hơn nền ở Dark, xám xanh nhạt ở Light.
  static Color get sunken =>
      _dark ? Colors.black.withValues(alpha: 0.28) : AppColors.surfaceContainer;

  /// Hai đầu gradient của thẻ kính.
  static Color get glassTop =>
      _dark ? Colors.white.withValues(alpha: 0.085) : AppColors.panel;
  static Color get glassBottom =>
      _dark ? Colors.white.withValues(alpha: 0.035) : AppColors.panelSecondary;

  static Color severityColor(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.normal:
        return ok;
      case AlertSeverity.warning:
        return warning;
      case AlertSeverity.critical:
        return critical;
    }
  }

  static Color cellColor(CellStatus s) {
    switch (s) {
      case CellStatus.ok:
        return ok;
      case CellStatus.warning:
        return warning;
      case CellStatus.critical:
        return critical;
      case CellStatus.invalid:
        return invalid;
    }
  }

  static Color freshnessColor(BmsFreshness f) {
    switch (f) {
      case BmsFreshness.live:
        return ok;
      case BmsFreshness.stale:
        return warning;
      case BmsFreshness.lost:
        return critical;
      case BmsFreshness.none:
        return invalid;
    }
  }

  static IconData freshnessIcon(BmsFreshness f) {
    switch (f) {
      case BmsFreshness.live:
        return Icons.sensors_rounded;
      case BmsFreshness.stale:
        return Icons.hourglass_bottom_rounded;
      case BmsFreshness.lost:
        return Icons.bluetooth_disabled_rounded;
      case BmsFreshness.none:
        return Icons.sensors_off_rounded;
    }
  }

  // ── Kiểu chữ ──────────────────────────────────────────────────────────────
  static TextStyle title([double size = 16, Color? color]) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: FontWeight.w700, color: color ?? text);

  static TextStyle body([double size = 13, Color? color]) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: FontWeight.w500, color: color ?? textDim, height: 1.35);

  static TextStyle number(
          [double size = 22, Color? color, FontWeight w = FontWeight.w700]) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: w,
        color: color ?? text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Chuyển màn hình mượt: mờ dần + trượt nhẹ từ dưới lên.
  static Route<T> route<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, anim, _, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}

/// Nền tối có chiều sâu: gradient dọc + hai quầng sáng mờ.
class BmsBackground extends StatelessWidget {
  final Widget child;
  const BmsBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Bms.bgGlow, Bms.bgMid, Bms.bg],
          stops: [0.0, 0.35, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Bms.accent.withValues(alpha: 0.16),
                    Bms.accent.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -120,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Bms.accent2.withValues(alpha: 0.10),
                    Bms.accent2.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Khối kính. [blur] bật làm mờ nền thật (tốn GPU hơn — chỉ dùng cho khối hero).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? glow;
  final bool blur;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.borderColor,
    this.glow,
    this.blur = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Bms.glassTop, Bms.glassBottom],
        ),
        border: Border.all(color: borderColor ?? Bms.border, width: 1),
        boxShadow: [
          // Light: bóng nhẹ như các Panel khác; Dark: không bóng (đã có viền kính).
          if (!AppColors.isDark) ...AppColors.cardShadow,
          if (glow != null)
            BoxShadow(
              color: glow!.withValues(alpha: 0.22),
              blurRadius: 22,
              spreadRadius: -4,
            ),
        ],
      ),
      child: child,
    );

    if (blur) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: content,
        ),
      );
    }
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: content,
        ),
      );
    }
    return content;
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Bms.accent, Bms.accent2],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Bms.textDim,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Nhãn nguồn dữ liệu: đo trực tiếp / tính toán / ước tính.
enum DataSource {
  measured('BMS đo', Icons.sensors_rounded),
  calculated('Tính toán', Icons.functions_rounded),
  estimated('Ước tính', Icons.auto_graph_rounded),
  unavailable('Không có', Icons.block_rounded);

  final String label;
  final IconData icon;
  const DataSource(this.label, this.icon);

  /// Màu theo palette đang áp dụng (getter vì Bms.* phụ thuộc sáng/tối).
  Color get color {
    switch (this) {
      case DataSource.measured:
        return Bms.accent;
      case DataSource.calculated:
        return Bms.textDim;
      case DataSource.estimated:
        return Bms.estimated;
      case DataSource.unavailable:
        return Bms.invalid;
    }
  }
}

class SourceTag extends StatelessWidget {
  final DataSource source;
  const SourceTag(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: source.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: source.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 10, color: source.color),
          const SizedBox(width: 3),
          Text(
            source.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: source.color,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const StatusPill({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FreshnessPill extends StatelessWidget {
  final BmsFreshness freshness;
  const FreshnessPill(this.freshness, {super.key});

  @override
  Widget build(BuildContext context) => StatusPill(
        text: freshness.label,
        color: Bms.freshnessColor(freshness),
        icon: Bms.freshnessIcon(freshness),
      );
}

/// "x giây trước" tự cập nhật mỗi giây, chỉ rebuild chính widget này.
class AgeText extends StatefulWidget {
  final DateTime? at;
  final TextStyle? style;
  final String prefix;
  const AgeText({super.key, required this.at, this.style, this.prefix = ''});

  /// Định dạng "x giây trước" dùng chung (protection_view gọi AgeText.format).
  static String format(DateTime at, DateTime now) => _AgeTextState.format(at, now);

  @override
  State<AgeText> createState() => _AgeTextState();
}

class _AgeTextState extends State<AgeText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String format(DateTime at, DateTime now) {
    final s = now.difference(at).inSeconds;
    if (s < 0) return 'vừa xong';
    if (s < 60) return '$s giây trước';
    if (s < 3600) return '${s ~/ 60} phút ${s % 60} giây trước';
    return '${s ~/ 3600} giờ ${(s % 3600) ~/ 60} phút trước';
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.at;
    return Text(
      at == null ? 'Chưa nhận dữ liệu' : '${widget.prefix}${format(at, DateTime.now())}',
      style: widget.style ?? Bms.body(11.5),
    );
  }
}

String formatClock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} giây';
  if (d.inMinutes < 60) return '${d.inMinutes} phút ${d.inSeconds % 60} giây';
  return '${d.inHours} giờ ${d.inMinutes % 60} phút';
}

/// Thông báo trạng thái dữ liệu ở đầu mỗi tab.
class DataStateBanner extends StatelessWidget {
  final BmsFreshness freshness;
  final DateTime? receivedAt;
  const DataStateBanner({super.key, required this.freshness, required this.receivedAt});

  @override
  Widget build(BuildContext context) {
    if (freshness == BmsFreshness.live) return const SizedBox.shrink();
    final c = Bms.freshnessColor(freshness);
    final String msg;
    switch (freshness) {
      case BmsFreshness.stale:
        msg = 'Gói BMS cuối đã cũ — các số liệu bên dưới KHÔNG phải số đo hiện tại.';
      case BmsFreshness.lost:
        msg = 'Đã mất kết nối với xe — hiển thị bản ghi cuối cùng, không phải dữ liệu trực tiếp.';
      case BmsFreshness.none:
        msg = 'Chưa nhận được gói BMS từ xe. Kết nối xe để xem dữ liệu cell thật.';
      case BmsFreshness.live:
        msg = '';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 16,
        borderColor: c.withValues(alpha: 0.45),
        child: Row(
          children: [
            Icon(Bms.freshnessIcon(freshness), color: c, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg, style: Bms.body(12.5, c)),
                  if (receivedAt != null) ...[
                    const SizedBox(height: 2),
                    AgeText(
                      at: receivedAt,
                      prefix: 'Gói cuối: ',
                      style: Bms.body(11, Bms.textDim),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
