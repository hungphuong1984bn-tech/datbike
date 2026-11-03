// Radar Smart Key — CHỈ TRÌNH BÀY. Không gửi lệnh, không đổi engine/ngưỡng.
//
// Trung thực về dữ liệu:
//  • BLE/RSSI chỉ cho biết KHOẢNG CÁCH ước lượng, KHÔNG biết HƯỚNG. Điểm điện
//    thoại luôn đặt ở một góc cố định và có ghi chú "không xác định hướng".
//  • Vòng mờ quanh điểm phản ánh độ tin cậy (thấp → vòng to).
//  • Chưa kết nối/xác thực hoặc chưa có mẫu → KHÔNG vẽ điểm, KHÔNG quét "tìm thấy".
//  • Dải mờ giữa vùng gần và vùng xa = vùng trễ (giữ nguyên trạng thái trước).
//  • Hiệu ứng quét tắt khi hệ thống bật "giảm chuyển động".

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/proximity/proximity_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets.dart';

class SmartKeyRadarCard extends StatelessWidget {
  final ProximitySnapshot prox;
  final bool connected; // đã kết nối + xác thực

  const SmartKeyRadarCard({
    super.key,
    required this.prox,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final dist = (connected && prox.rangeStrict) ? prox.distanceM : null;
    final within = dist == null ? null : prox.withinRange;
    final Color tone = dist == null
        ? AppColors.textMuted
        : (within ?? true)
            ? AppColors.tertiary
            : AppColors.red;
    final limit = prox.rangeLimitM;
    final limitTxt =
        limit.toStringAsFixed(limit == limit.roundToDouble() ? 0 : 1);

    final String headline;
    final String sub;
    if (!connected) {
      headline = '--';
      sub = 'Chưa kết nối/xác thực xe — radar tạm dừng';
    } else if (!prox.rangeStrict) {
      headline = '--';
      sub = 'Chế độ giới hạn khoảng cách đang tắt';
    } else if (dist == null) {
      headline = '--';
      sub = 'Đang chờ mẫu tín hiệu để ước lượng khoảng cách';
    } else {
      headline = '≈ ${dist.toStringAsFixed(1)} m';
      sub = (within ?? true)
          ? 'Trong vùng nhận diện ($limitTxt m)'
          : 'Ngoài vùng nhận diện ($limitTxt m)';
    }

    return Panel(
      key: const Key('smart_key_radar_card'),
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
              child: _Radar(
              distanceM: dist,
              limitM: limit,
              nearM: prox.nearZoneM,
              farM: prox.farZoneM,
              confidence: prox.distanceConfidence,
              tone: tone,
              sweeping: connected && prox.rangeStrict,
              semanticLabel: dist == null
                  ? 'Radar Smart Key: chưa có khoảng cách'
                  : 'Radar Smart Key: khoảng ${dist.toStringAsFixed(1)} mét, $sub',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            key: const Key('smart_key_radar_distance'),
            style: AppTypography.evWide(
              fontSize: 30,
              color: dist == null ? AppColors.textMuted : AppColors.readable(tone),
            ),
          ),
          const SizedBox(height: 2),
          Text(sub,
              textAlign: TextAlign.center,
              style: AppTypography.labelMd(color: AppColors.textSecondary)),
          if (dist != null) ...[
            const SizedBox(height: 4),
            Text(
              'Độ tin cậy ${(prox.distanceConfidence * 100).round()}% · '
              'chỉ đo khoảng cách, không xác định hướng',
              textAlign: TextAlign.center,
              style: AppTypography.labelSm(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Radar extends StatefulWidget {
  final double? distanceM;
  final double limitM;
  final double nearM;
  final double farM;
  final double confidence;
  final Color tone;
  final bool sweeping;
  final String semanticLabel;

  const _Radar({
    required this.distanceM,
    required this.limitM,
    required this.nearM,
    required this.farM,
    required this.confidence,
    required this.tone,
    required this.sweeping,
    required this.semanticLabel,
  });

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  void _sync() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldRun = widget.sweeping && !reduce;
    if (shouldRun && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!shouldRun && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Radar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  size: Size.infinite,
                  painter: _RadarPainter(
                    sweep: widget.sweeping ? _ctrl.value : null,
                    distanceM: widget.distanceM,
                    limitM: widget.limitM,
                    nearM: widget.nearM,
                    farM: widget.farM,
                    confidence: widget.confidence,
                    tone: widget.tone,
                    ring: AppColors.isDark
                        ? AppColors.panelBorderBright
                        : AppColors.panelBorder,
                    label: AppColors.textMuted,
                    accent: AppColors.cyan,
                  ),
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.panel,
                  border: Border.all(color: widget.tone.withValues(alpha: 0.8)),
                ),
                child: Icon(Icons.two_wheeler_rounded,
                    size: 26, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double? sweep; // 0..1, null = không quét
  final double? distanceM;
  final double limitM;
  final double nearM;
  final double farM;
  final double confidence;
  final Color tone;
  final Color ring;
  final Color label;
  final Color accent;

  const _RadarPainter({
    required this.sweep,
    required this.distanceM,
    required this.limitM,
    required this.nearM,
    required this.farM,
    required this.confidence,
    required this.tone,
    required this.ring,
    required this.label,
    required this.accent,
  });

  static const _dotAngle = -math.pi / 4; // cố định: không biết hướng thật

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 4;
    final maxM = limitM * 2;
    final scale = r / maxM;

    // Nền
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          accent.withValues(alpha: 0.10),
          accent.withValues(alpha: 0.02),
        ]).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Dải trễ giữa vùng gần và vùng xa
    final nearR = (nearM * scale).clamp(0.0, r);
    final farR = (farM * scale).clamp(0.0, r);
    if (farR > nearR) {
      canvas.drawCircle(
        c,
        (nearR + farR) / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = farR - nearR
          ..color = tone.withValues(alpha: 0.14),
      );
    }

    // Vòng chia 4 mức + chữ mét
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring.withValues(alpha: 0.7);
    for (var k = 1; k <= 4; k++) {
      canvas.drawCircle(c, r * k / 4, ringPaint);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), ringPaint);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), ringPaint);

    // Vòng giới hạn (nhấn)
    canvas.drawCircle(
      c,
      limitM * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = tone.withValues(alpha: 0.9),
    );
    for (var k = 1; k <= 4; k++) {
      final m = maxM * k / 4;
      _text(canvas, '${m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1)} m',
          Offset(c.dx + 4, c.dy - r * k / 4 - 12), label, 10);
    }

    // Quét
    if (sweep != null) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(sweep! * math.pi * 2);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = SweepGradient(
            colors: [
              accent.withValues(alpha: 0.0),
              accent.withValues(alpha: 0.0),
              accent.withValues(alpha: 0.22),
            ],
            stops: const [0.0, 0.75, 1.0],
          ).createShader(rect),
      );
      canvas.restore();
    }

    // Điện thoại: chỉ vẽ khi có khoảng cách thật
    final d = distanceM;
    if (d != null) {
      final dm = d.clamp(0.0, maxM);
      final p = Offset(c.dx + math.cos(_dotAngle) * dm * scale,
          c.dy + math.sin(_dotAngle) * dm * scale);
      final halo = 8 + (1 - confidence.clamp(0.0, 1.0)) * 16;
      canvas.drawCircle(p, halo, Paint()..color = tone.withValues(alpha: 0.18));
      canvas.drawCircle(p, 6.5, Paint()..color = tone);
      canvas.drawCircle(
        p,
        6.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter o) =>
      o.sweep != sweep ||
      o.distanceM != distanceM ||
      o.limitM != limitM ||
      o.nearM != nearM ||
      o.farM != farM ||
      o.confidence != confidence ||
      o.tone != tone ||
      o.ring != ring ||
      o.label != label ||
      o.accent != accent;
}
