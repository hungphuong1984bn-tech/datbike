// EnergyBattery — mô hình pin có dải năng lượng chạy khi đang sạc.
// Chỉ nhận số liệu từ ngoài; [percent] == null → khung pin rỗng (chưa có dữ liệu).
// Animation chỉ chạy khi [charging] và hệ thống không tắt hiệu ứng.

import 'package:flutter/material.dart';

import '../app_theme.dart';

class EnergyBattery extends StatefulWidget {
  final double? percent; // 0..100
  final bool charging;
  final Color color;
  final double height;

  const EnergyBattery({
    super.key,
    required this.percent,
    required this.charging,
    required this.color,
    this.height = 96,
  });

  @override
  State<EnergyBattery> createState() => _EnergyBatteryState();
}

class _EnergyBatteryState extends State<EnergyBattery>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  void _sync() {
    final reduce = MediaQuery.of(context).disableAnimations;
    final run = widget.charging && !reduce;
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EnergyBattery old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = ((widget.percent ?? 0) / 100).clamp(0.0, 1.0);
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: AppMotion.slow * 2,
          curve: AppMotion.curve,
          builder: (_, level, __) => AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _BatteryPainter(
                level: level,
                hasData: widget.percent != null,
                charging: widget.charging,
                flow: _c.value,
                color: widget.color,
                outline: AppColors.panelBorderBright,
                track: AppColors.panelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final double level;
  final bool hasData;
  final bool charging;
  final double flow;
  final Color color;
  final Color outline;
  final Color track;

  _BatteryPainter({
    required this.level,
    required this.hasData,
    required this.charging,
    required this.flow,
    required this.color,
    required this.outline,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const capW = 8.0;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - capW - 3, size.height),
      const Radius.circular(18),
    );
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - capW, size.height * 0.32, capW,
          size.height * 0.36),
      const Radius.circular(4),
    );

    if (charging && hasData) {
      canvas.drawRRect(
        body,
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }
    canvas.drawRRect(body, Paint()..color = track);

    if (hasData && level > 0) {
      final inner = body.deflate(5);
      canvas.save();
      canvas.clipRRect(inner);
      final fillW = inner.width * level;
      final fillRect = Rect.fromLTWH(inner.left, inner.top, fillW, inner.height);
      canvas.drawRect(
        fillRect,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0.70), color],
          ).createShader(fillRect),
      );
      if (charging) {
        // Dải sáng chạy từ trái sang phải trong phần đã đầy.
        final bandW = (fillW * 0.35).clamp(24.0, 90.0);
        final x = inner.left - bandW + (fillW + bandW) * flow;
        final band = Rect.fromLTWH(x, inner.top, bandW, inner.height);
        canvas.drawRect(
          band.intersect(fillRect),
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.38),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(band),
        );
      }
      canvas.restore();
    }

    // Vạch chia 10 ô cho cảm giác "cell".
    final sep = Paint()
      ..color = track.withValues(alpha: 0.9)
      ..strokeWidth = 2;
    final inner = body.deflate(5);
    for (var i = 1; i < 10; i++) {
      final x = inner.left + inner.width * i / 10;
      canvas.drawLine(Offset(x, inner.top), Offset(x, inner.bottom), sep);
    }

    canvas.drawRRect(
      body,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRRect(cap, Paint()..color = outline);
  }

  @override
  bool shouldRepaint(_BatteryPainter o) =>
      o.level != level ||
      o.flow != flow ||
      o.charging != charging ||
      o.hasData != hasData ||
      o.color != color ||
      o.outline != outline;
}
