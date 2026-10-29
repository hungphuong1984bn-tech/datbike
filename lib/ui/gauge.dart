// Gauge tốc độ kỹ thuật số Kinetic Stitch EV:
// Vạch chia độ chuẩn xác, đường ray hairline thanh thoát, gradient Electric Azure & Cyan,
// hiển thị số km/h bằng Space Grotesk với tabular figures chống rung giật khi tăng tốc.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

class SpeedGauge extends StatelessWidget {
  final double speed; // km/h
  final double maxSpeed;
  final Widget? center;
  final double size;

  const SpeedGauge({
    super.key,
    required this.speed,
    this.maxSpeed = 100,
    this.center,
    this.size = 240,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _KineticGaugePainter(
              progress: (speed / maxSpeed).clamp(0.0, 1.0),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: center ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      speed.toStringAsFixed(1),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: (size * 0.24).clamp(40.0, 56.0),
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'KM/H',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textDim,
                        fontSize: (size * 0.05).clamp(11.0, 13.0),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.06 * 12,
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

class _KineticGaugePainter extends CustomPainter {
  final double progress;
  // Ghi nhận chế độ sáng/tối lúc tạo để vẽ lại khi đổi theme (màu đọc trong paint()).
  final bool _dark = AppColors.isDark;
  _KineticGaugePainter({required this.progress});

  static const _start = 140 * pi / 180; // 140°
  static const _sweep = 260 * pi / 180; // tới 400°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 250.0;
    final strokeTrack = (10.0 * scale).clamp(6.0, 12.0);
    final margin = (16.0 * scale).clamp(10.0, 18.0);
    final radius = size.width / 2 - margin;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Đường ray viền ngoài hairline mảnh
    final outerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.panelBorder;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + (8.0 * scale).clamp(5.0, 9.0)),
      _start,
      _sweep,
      false,
      outerRing,
    );

    // 2. Track rãnh nền chính (soft container fill)
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeTrack
      ..strokeCap = StrokeCap.round
      ..color = AppColors.panelSecondary;
    canvas.drawArc(rect, _start, _sweep, false, track);

    // 3. Vạch khía (Tick marks) chia độ 0 -> 100 km/h
    final tickPaint = Paint()
      ..color = AppColors.panelBorderBright
      ..strokeWidth = (1.2 * scale).clamp(0.8, 1.5);
    final activeTickPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = (2.0 * scale).clamp(1.5, 2.5);

    const tickCount = 20;
    final tickOffset = (14.0 * scale).clamp(9.0, 16.0);
    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = _start + _sweep * t;
      final isMajor = i % 4 == 0;
      final len = isMajor ? (8.0 * scale).clamp(5.0, 9.0) : (4.0 * scale).clamp(2.5, 5.0);
      final rInner = radius - tickOffset - len;
      final rOuter = radius - tickOffset;

      final p1 = Offset(center.dx + rInner * cos(angle), center.dy + rInner * sin(angle));
      final p2 = Offset(center.dx + rOuter * cos(angle), center.dy + rOuter * sin(angle));
      canvas.drawLine(p1, p2, t <= progress ? activeTickPaint : tickPaint);
    }

    // 4. Thanh tốc độ tiến độ (Progress bar) Electric Azure & Cyan
    if (progress > 0.01) {
      // Glow nhẹ chuẩn Kinetic Stitch
      final glowWidth = (14.0 * scale).clamp(8.0, 16.0);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = glowWidth
        ..strokeCap = StrokeCap.round
        ..color = AppColors.secondary.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(rect, _start, _sweep * progress, false, glow);

      final bar = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeTrack
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [AppColors.secondary, AppColors.primary],
          transform: GradientRotation(_start),
        ).createShader(rect);
      canvas.drawArc(rect, _start, _sweep * progress, false, bar);

      // Điểm chỉ báo đầu kim (Tip pointer)
      final tipAngle = _start + _sweep * progress;
      final tipPoint = Offset(center.dx + radius * cos(tipAngle), center.dy + radius * sin(tipAngle));
      final tipDotRadius = (5.0 * scale).clamp(3.5, 6.0);
      final tipPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final tipBorder = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.5 * scale).clamp(1.8, 3.0);

      canvas.drawCircle(tipPoint, tipDotRadius, tipPaint);
      canvas.drawCircle(tipPoint, tipDotRadius, tipBorder);
    }
  }

  @override
  bool shouldRepaint(_KineticGaugePainter old) => old.progress != progress || old._dark != _dark;
}
