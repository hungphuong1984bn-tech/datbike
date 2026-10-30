// Biểu đồ vẽ bằng CustomPainter (không thêm thư viện ngoài): đồ thị đường theo
// thời gian và biểu đồ so sánh điện áp các cell.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/battery/cell_model.dart';
import '../bms_theme.dart';

class ChartSeries {
  final String label;
  final List<double> values;
  final Color color;
  final bool dashed;
  final bool fill;
  const ChartSeries({
    required this.label,
    required this.values,
    required this.color,
    this.dashed = false,
    this.fill = false,
  });
}

void _drawText(
  Canvas canvas,
  String text,
  Offset at, {
  Color color = Bms.textFaint,
  double size = 10,
  TextAlign align = TextAlign.left,
  double maxWidth = 80,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: GoogleFonts.spaceGrotesk(fontSize: size, color: color),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  final dx = align == TextAlign.right ? at.dx - tp.width : at.dx;
  tp.paint(canvas, Offset(dx, at.dy));
}

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
    {double dash = 5, double gap = 4}) {
  final total = (b - a).distance;
  if (total <= 0) return;
  final dir = (b - a) / total;
  var d = 0.0;
  while (d < total) {
    final e = math.min(d + dash, total);
    canvas.drawLine(a + dir * d, a + dir * e, paint);
    d += dash + gap;
  }
}

/// Đồ thị đường nhiều chuỗi, trục Y tự co giãn quanh dữ liệu (KHÔNG bắt đầu từ 0).
class BmsLineChart extends StatelessWidget {
  final List<ChartSeries> series;
  final double height;
  final double minSpan;
  final int fractionDigits;
  final String unit;
  final String? leftCaption;
  final String? rightCaption;

  const BmsLineChart({
    super.key,
    required this.series,
    this.height = 170,
    this.minSpan = 0.02,
    this.fractionDigits = 3,
    this.unit = '',
    this.leftCaption,
    this.rightCaption,
  });

  @override
  Widget build(BuildContext context) {
    final enough = series.any((s) => s.values.length >= 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: enough
              ? RepaintBoundary(
                  child: CustomPaint(
                    painter: _LinePainter(
                      series: series,
                      minSpan: minSpan,
                      digits: fractionDigits,
                      unit: unit,
                    ),
                  ),
                )
              : Center(
                  child: Text('Đang thu thập mẫu… (cần ≥ 2 gói BMS)',
                      style: Bms.body(12, Bms.textFaint)),
                ),
        ),
        if (leftCaption != null || rightCaption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 44),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(leftCaption ?? '', style: Bms.body(10.5, Bms.textFaint)),
                Text(rightCaption ?? '', style: Bms.body(10.5, Bms.textFaint)),
              ],
            ),
          ),
        if (series.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 3,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(s.label, style: Bms.body(11)),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<ChartSeries> series;
  final double minSpan;
  final int digits;
  final String unit;

  _LinePainter({
    required this.series,
    required this.minSpan,
    required this.digits,
    required this.unit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0;
    const top = 8.0;
    const bottom = 6.0;
    final plot = Rect.fromLTRB(left, top, size.width - 6, size.height - bottom);

    var lo = double.infinity;
    var hi = -double.infinity;
    var maxLen = 0;
    for (final s in series) {
      maxLen = math.max(maxLen, s.values.length);
      for (final v in s.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (!lo.isFinite || !hi.isFinite || maxLen < 2) return;
    var span = hi - lo;
    if (span < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
      span = minSpan;
    }
    final pad = span * 0.12;
    lo -= pad;
    hi += pad;
    final range = hi - lo;

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final v = hi - range * i / 3;
      _drawText(
        canvas,
        '${v.toStringAsFixed(digits)}$unit',
        Offset(left - 6, y - 6),
        align: TextAlign.right,
        maxWidth: left - 6,
      );
    }

    double xOf(int i, int n) =>
        plot.left + plot.width * (n <= 1 ? 0 : i / (n - 1));
    double yOf(double v) => plot.bottom - plot.height * ((v - lo) / range);

    for (final s in series) {
      final n = s.values.length;
      if (n < 2) continue;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = Offset(xOf(i, n), yOf(s.values[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }

      if (s.fill) {
        final area = Path.from(path)
          ..lineTo(xOf(n - 1, n), plot.bottom)
          ..lineTo(xOf(0, n), plot.bottom)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.color.withValues(alpha: 0.28),
                s.color.withValues(alpha: 0.0),
              ],
            ).createShader(plot),
        );
      }

      final line = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.dashed ? 1.4 : 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;

      if (s.dashed) {
        for (var i = 1; i < n; i += 2) {
          // Đường đứt nét đơn giản: vẽ xen kẽ từng đoạn.
          canvas.drawLine(
            Offset(xOf(i - 1, n), yOf(s.values[i - 1])),
            Offset(xOf(i, n), yOf(s.values[i])),
            line,
          );
        }
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color.withValues(alpha: 0.28)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawPath(path, line);
        final last = Offset(xOf(n - 1, n), yOf(s.values.last));
        canvas.drawCircle(last, 4.5, Paint()..color = s.color);
        canvas.drawCircle(
            last, 8, Paint()..color = s.color.withValues(alpha: 0.25));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

/// So sánh điện áp các cell: cột theo trạng thái, vạch đứt = điện áp trung bình.
/// Trục Y được cắt quanh dữ liệu để thấy chênh lệch mV (không bắt đầu từ 0 V).
class CellCompareChart extends StatelessWidget {
  final List<CellSnapshot> cells;
  final double average;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;
  final double height;

  const CellCompareChart({
    super.key,
    required this.cells,
    required this.average,
    this.selectedIndex,
    this.onSelect,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Chưa có dữ liệu cell', style: Bms.body(12, Bms.textFaint)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        const plotLeft = 44.0;
        final plotW = c.maxWidth - plotLeft - 6;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onSelect == null
              ? null
              : (d) {
                  final x = d.localPosition.dx - plotLeft;
                  if (x < 0 || x > plotW) return;
                  final i = (x / (plotW / cells.length)).floor();
                  if (i >= 0 && i < cells.length) onSelect!(i);
                },
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CompareBarsPainter(
                  cells: cells,
                  average: average,
                  selected: selectedIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompareBarsPainter extends CustomPainter {
  final List<CellSnapshot> cells;
  final double average;
  final int? selected;

  _CompareBarsPainter({
    required this.cells,
    required this.average,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0;
    const top = 8.0;
    const bottom = 18.0;
    final plot = Rect.fromLTRB(left, top, size.width - 6, size.height - bottom);

    var lo = double.infinity;
    var hi = -double.infinity;
    for (final c in cells) {
      if (!c.valid) continue;
      if (c.voltage < lo) lo = c.voltage;
      if (c.voltage > hi) hi = c.voltage;
    }
    if (!lo.isFinite || !hi.isFinite) return;
    var span = hi - lo;
    const minSpan = 0.02;
    if (span < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
      span = minSpan;
    }
    final pad = span * 0.25;
    lo -= pad;
    hi += pad;
    final range = hi - lo;
    double yOf(double v) => plot.bottom - plot.height * ((v - lo) / range);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _drawText(canvas, (hi - range * i / 3).toStringAsFixed(3),
          Offset(left - 6, y - 6),
          align: TextAlign.right, maxWidth: left - 6);
    }

    final n = cells.length;
    final slot = plot.width / n;
    final barW = math.max(2.0, math.min(slot * 0.62, 22.0));
    for (var i = 0; i < n; i++) {
      final c = cells[i];
      final cx = plot.left + slot * (i + 0.5);
      if (!c.valid) {
        _drawText(canvas, '×', Offset(cx - 3, plot.bottom - 14),
            color: Bms.invalid, size: 12);
        continue;
      }
      final color = Bms.cellColor(c.status);
      final y = yOf(c.voltage);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(cx - barW / 2, y, cx + barW / 2, plot.bottom),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.25)],
          ).createShader(rect.outerRect),
      );
      if (i == selected) {
        canvas.drawRRect(
          rect.inflate(2),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      if (n <= 30 && (n <= 12 || i % 2 == 0)) {
        _drawText(canvas, '${i + 1}', Offset(cx - 4, plot.bottom + 3),
            size: 9.5, maxWidth: 20);
      }
    }

    if (average > 0) {
      final y = yOf(average);
      _dashedLine(
        canvas,
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = Bms.accent
          ..strokeWidth = 1.4,
      );
      _drawText(canvas, 'TB', Offset(plot.right - 16, y - 13),
          color: Bms.accent, size: 10);
    }
  }

  @override
  bool shouldRepaint(covariant _CompareBarsPainter old) => true;
}
