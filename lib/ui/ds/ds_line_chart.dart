// DsLineChart — biểu đồ đường dùng chung (sạc, vận hành, pin).
// Chỉ vẽ dữ liệu được truyền vào; rỗng → hiện [emptyText], KHÔNG tạo dữ liệu giả.
// Hiệu ứng "vẽ dần" chạy một lần khi biểu đồ xuất hiện (đổi [animationKey] để chạy lại).

import 'package:flutter/material.dart';

import '../app_theme.dart';

class DsLineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final String unit;
  final int decimals;
  final double height;
  final double? minY;
  final double? maxY;
  final String emptyText;
  final String? caption; // chú thích trục thời gian, vd. "15 phút gần nhất"
  final Object? animationKey;

  const DsLineChart({
    super.key,
    required this.values,
    required this.color,
    this.unit = '',
    this.decimals = 0,
    this.height = 150,
    this.minY,
    this.maxY,
    this.emptyText = 'Chưa có dữ liệu để vẽ biểu đồ',
    this.caption,
    this.animationKey,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(emptyText,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(color: AppColors.textSecondary)),
        ),
      );
    }
    final reduce = MediaQuery.of(context).disableAnimations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              key: ValueKey<Object?>(animationKey),
              tween: Tween<double>(begin: reduce ? 1 : 0, end: 1),
              duration: AppMotion.slow * 2,
              curve: AppMotion.curve,
              builder: (_, t, __) => CustomPaint(
                size: Size.infinite,
                painter: _LinePainter(
                  values: values,
                  color: color,
                  unit: unit,
                  decimals: decimals,
                  minY: minY,
                  maxY: maxY,
                  progress: t,
                  grid: AppColors.panelBorder,
                  label: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(caption!,
                textAlign: TextAlign.end,
                style: AppTypography.labelSm(color: AppColors.textMuted)),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final String unit;
  final int decimals;
  final double? minY;
  final double? maxY;
  final double progress;
  final Color grid;
  final Color label;

  _LinePainter({
    required this.values,
    required this.color,
    required this.unit,
    required this.decimals,
    required this.minY,
    required this.maxY,
    required this.progress,
    required this.grid,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var lo = minY ?? values.reduce((a, b) => a < b ? a : b);
    var hi = maxY ?? values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    } else if (minY == null || maxY == null) {
      final pad = (hi - lo) * 0.12;
      if (minY == null) lo -= pad;
      if (maxY == null) hi += pad;
    }

    const leftPad = 40.0;
    const topPad = 6.0;
    const bottomPad = 6.0;
    final w = size.width - leftPad;
    final h = size.height - topPad - bottomPad;
    if (w <= 0 || h <= 0) return;

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = topPad + h * i / 2;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final v = hi - (hi - lo) * i / 2;
      _text(canvas, v.toStringAsFixed(decimals), Offset(0, y - 6));
    }

    final n = values.length;
    final shown = (n * progress).clamp(2, n).toInt();
    Offset pt(int i) {
      final x = leftPad + w * i / (n - 1);
      final y = topPad + h * (1 - ((values[i] - lo) / (hi - lo)).clamp(0.0, 1.0));
      return Offset(x, y);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < shown; i++) {
      final p = pt(i);
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(pt(shown - 1).dx, topPad + h)
      ..lineTo(pt(0).dx, topPad + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(leftPad, topPad, w, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = pt(shown - 1);
    canvas.drawCircle(end, 5, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(end, 3, Paint()..color = color);
  }

  void _text(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: 10, color: label),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 38);
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.progress != progress ||
      old.color != color ||
      old.grid != grid;
}
