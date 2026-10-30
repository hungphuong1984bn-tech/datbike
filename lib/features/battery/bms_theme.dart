// Bộ giao diện "Premium EV Battery Monitoring": nền tối có chiều sâu, khối kính
// (glassmorphism), màu trạng thái và các widget nhỏ dùng chung cho màn hình BMS.
// Độc lập với palette sáng/tối của app: màn hình BMS luôn dùng Dark Premium.

import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/battery/cell_model.dart';
import '../../core/battery/cell_protection_engine.dart';

class Bms {
  Bms._();

  static const Color bg = Color(0xFF060A12);
  static const Color bgMid = Color(0xFF0B1220);
  static const Color bgGlow = Color(0xFF111B33);

  static const Color text = Color(0xFFEAF0FA);
  static const Color textDim = Color(0xFF8FA0BC);
  static const Color textFaint = Color(0xFF5B6B86);

  static const Color accent = Color(0xFF38BDF8);
  static const Color accent2 = Color(0xFF8B5CF6);

  static const Color ok = Color(0xFF22D3A0);
  static const Color warning = Color(0xFFFBBF24);
  static const Color critical = Color(0xFFF43F5E);
  static const Color invalid = Color(0xFF64748B);
  static const Color estimated = Color(0xFFA78BFA);

  static const Color border = Color(0x1FFFFFFF); // trắng 12%
  static const Color glassFill = Color(0x0FFFFFFF); // trắng 6%

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
  static TextStyle title([double size = 16, Color color = text]) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: FontWeight.w700, color: color);

  static TextStyle body([double size = 13, Color color = textDim]) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: FontWeight.w500, color: color, height: 1.35);

  static TextStyle number(
          [double size = 22, Color color = text, FontWeight w = FontWeight.w700]) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: w,
        color: color,
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
      decoration: const BoxDecoration(
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
          colors: [
            Colors.white.withValues(alpha: 0.085),
            Colors.white.withValues(alpha: 0.035),
          ],
        ),
        border: Border.all(color: borderColor ?? Bms.border, width: 1),
        boxShadow: glow == null
            ? null
            : [
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
              gradient: const LinearGradient(
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
  measured('BMS đo', Bms.accent, Icons.sensors_rounded),
  calculated('Tính toán', Bms.textDim, Icons.functions_rounded),
  estimated('Ước tính', Bms.estimated, Icons.auto_graph_rounded),
  unavailable('Không có', Bms.invalid, Icons.block_rounded);

  final String label;
  final Color color;
  final IconData icon;
  const DataSource(this.label, this.color, this.icon);
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
