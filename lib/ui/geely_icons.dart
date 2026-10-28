import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Bộ Icon vector vẽ tay chuẩn phong cách EV Companion App (Geely / Zeekr / Porsche EV).
/// Nét vẽ thanh mảnh (stroke 1.8dp - 2.0dp), bo góc mềm mại, độ phân giải sắc nét
/// ở mọi kích thước, thay thế hoàn toàn các icon thô mặc định của Material.
class GeelyIcons {
  GeelyIcons._();

  /// Khóa (ổ khóa đóng)
  static Widget lock({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _LockPainter(isOpen: false),
    );
  }

  /// Mở khóa (ổ khóa mở)
  static Widget lockOpen({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _LockPainter(isOpen: true),
    );
  }

  /// Tìm xe (Loa phát sóng âm thanh)
  static Widget findBike({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _FindBikePainter(),
    );
  }

  /// Sạc pin (Tia sét EV sắc nét)
  static Widget charging({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _ChargingBoltPainter(),
    );
  }

  /// Đồng bộ giờ Taplo (Mặt đồng hồ 2 kim thanh mảnh)
  static Widget clock({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _ClockPainter(),
    );
  }

  /// Mở cốp / Yên xe
  static Widget trunk({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _TrunkPainter(),
    );
  }

  /// Quạt gió / Hệ thống làm mát
  static Widget fan({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _FanPainter(),
    );
  }

  /// Xe máy điện (Biểu tượng xe hai bánh khí động học)
  static Widget bike({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _BikePainter(),
    );
  }

  /// Pin EV (Khối pin capsule với các vạch năng lượng)
  static Widget battery({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _BatteryPainter(),
    );
  }

  /// Đồng hồ tốc độ / ODO
  static Widget speedometer({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _SpeedometerPainter(),
    );
  }

  /// Khiên bảo vệ an toàn / Chống trộm
  static Widget shield({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _ShieldPainter(),
    );
  }

  /// Thẻ NFC / Sóng quẹt thẻ không tiếp xúc
  static Widget nfc({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _NfcPainter(),
    );
  }

  /// Cài đặt hệ thống (Cặp thanh trượt EV)
  static Widget settings({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _SettingsPainter(),
    );
  }

  /// Người dùng / Profile
  static Widget profile({double size = 22, Color? color}) {
    return _IconWrapper(
      size: size,
      color: color,
      painter: _ProfilePainter(),
    );
  }
}

class _IconWrapper extends StatelessWidget {
  final double size;
  final Color? color;
  final CustomPainter painter;

  const _IconWrapper({
    required this.size,
    required this.painter,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color ?? Colors.white;
    return CustomPaint(
      size: Size(size, size),
      painter: _ColorAwarePainter(painter: painter, color: iconColor),
    );
  }
}

class _ColorAwarePainter extends CustomPainter {
  final CustomPainter painter;
  final Color color;

  _ColorAwarePainter({required this.painter, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (painter is _BaseGeelyPainter) {
      (painter as _BaseGeelyPainter).color = color;
    }
    painter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ColorAwarePainter oldDelegate) =>
      color != oldDelegate.color;
}

abstract class _BaseGeelyPainter extends CustomPainter {
  Color color = Colors.white;

  Paint createStroke(double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint createFill() => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -------------------------------------------------------------
// 1. Lock Painter
// -------------------------------------------------------------
class _LockPainter extends _BaseGeelyPainter {
  final bool isOpen;
  _LockPainter({required this.isOpen});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Thân khóa (hình chữ nhật bo góc)
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.42, w * 0.64, h * 0.48),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(bodyRRect, stroke);

    // Lỗ khóa trung tâm
    final fill = createFill();
    canvas.drawCircle(Offset(w * 0.5, h * 0.61), w * 0.05, fill);
    final keyholePath = Path()
      ..moveTo(w * 0.47, h * 0.62)
      ..lineTo(w * 0.53, h * 0.62)
      ..lineTo(w * 0.52, h * 0.74)
      ..lineTo(w * 0.48, h * 0.74)
      ..close();
    canvas.drawPath(keyholePath, fill);

    // Càng khóa
    final shacklePath = Path();
    if (!isOpen) {
      shacklePath.moveTo(w * 0.32, h * 0.42);
      shacklePath.lineTo(w * 0.32, h * 0.26);
      shacklePath.arcToPoint(
        Offset(w * 0.68, h * 0.26),
        radius: Radius.circular(w * 0.18),
      );
      shacklePath.lineTo(w * 0.68, h * 0.42);
    } else {
      shacklePath.moveTo(w * 0.32, h * 0.42);
      shacklePath.lineTo(w * 0.32, h * 0.22);
      shacklePath.arcToPoint(
        Offset(w * 0.68, h * 0.22),
        radius: Radius.circular(w * 0.18),
      );
      shacklePath.lineTo(w * 0.68, h * 0.30);
    }
    canvas.drawPath(shacklePath, stroke);
  }
}

// -------------------------------------------------------------
// 2. Find Bike Painter (Megaphone + Sóng âm)
// -------------------------------------------------------------
class _FindBikePainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Loa chính
    final hornPath = Path()
      ..moveTo(w * 0.12, h * 0.38)
      ..lineTo(w * 0.28, h * 0.38)
      ..lineTo(w * 0.52, h * 0.18)
      ..lineTo(w * 0.52, h * 0.82)
      ..lineTo(w * 0.28, h * 0.62)
      ..lineTo(w * 0.12, h * 0.62)
      ..close();
    canvas.drawPath(hornPath, stroke);

    // Sóng âm 1
    final wave1 = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(w * 0.48, h * 0.5), radius: w * 0.20),
        -math.pi / 4,
        math.pi / 2,
      );
    canvas.drawPath(wave1, stroke);

    // Sóng âm 2
    final wave2 = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(w * 0.48, h * 0.5), radius: w * 0.34),
        -math.pi / 4,
        math.pi / 2,
      );
    canvas.drawPath(wave2, stroke);
  }
}

// -------------------------------------------------------------
// 3. Charging Bolt Painter
// -------------------------------------------------------------
class _ChargingBoltPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    final path = Path()
      ..moveTo(w * 0.58, h * 0.08)
      ..lineTo(w * 0.26, h * 0.52)
      ..lineTo(w * 0.48, h * 0.52)
      ..lineTo(w * 0.38, h * 0.92)
      ..lineTo(w * 0.74, h * 0.44)
      ..lineTo(w * 0.52, h * 0.44)
      ..close();

    canvas.drawPath(path, stroke);
  }
}

// -------------------------------------------------------------
// 4. Clock Painter
// -------------------------------------------------------------
class _ClockPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Vành đồng hồ tròn
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.40, stroke);

    // Kim giờ (hướng 3h)
    canvas.drawLine(
      Offset(w * 0.5, h * 0.5),
      Offset(w * 0.72, h * 0.5),
      stroke,
    );

    // Kim phút (hướng 12h)
    canvas.drawLine(
      Offset(w * 0.5, h * 0.5),
      Offset(w * 0.5, h * 0.24),
      stroke,
    );

    // Trục kim tâm
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.05, createFill());
  }
}

// -------------------------------------------------------------
// 5. Trunk Painter (Yên cốp xe)
// -------------------------------------------------------------
class _TrunkPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Đáy khoang cốp
    final base = Path()
      ..moveTo(w * 0.15, h * 0.56)
      ..lineTo(w * 0.22, h * 0.82)
      ..lineTo(w * 0.78, h * 0.82)
      ..lineTo(w * 0.85, h * 0.56);
    canvas.drawPath(base, stroke);

    // Nắp cốp mở nghiêng
    final lid = Path()
      ..moveTo(w * 0.15, h * 0.56)
      ..lineTo(w * 0.70, h * 0.26)
      ..lineTo(w * 0.82, h * 0.32);
    canvas.drawPath(lid, stroke);

    // Mũi tên chỉ hướng mở cốp
    final arrow = Path()
      ..moveTo(w * 0.46, h * 0.62)
      ..lineTo(w * 0.46, h * 0.44)
      ..moveTo(w * 0.38, h * 0.50)
      ..lineTo(w * 0.46, h * 0.42)
      ..lineTo(w * 0.54, h * 0.50);
    canvas.drawPath(arrow, createStroke(w * 0.075));
  }
}

// -------------------------------------------------------------
// 6. Fan Painter
// -------------------------------------------------------------
class _FanPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.08);

    // Tâm quạt
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.12, stroke);

    // 4 cánh quạt cong
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      canvas.save();
      canvas.translate(w * 0.5, h * 0.5);
      canvas.rotate(angle);

      final blade = Path()
        ..moveTo(0, -w * 0.12)
        ..quadraticBezierTo(w * 0.18, -w * 0.28, w * 0.06, -w * 0.42)
        ..quadraticBezierTo(-w * 0.10, -w * 0.32, 0, -w * 0.12);
      canvas.drawPath(blade, stroke);

      canvas.restore();
    }
  }
}

// -------------------------------------------------------------
// 7. Bike Painter (Electric Motorbike Contour)
// -------------------------------------------------------------
class _BikePainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.08);

    // Bánh sau
    canvas.drawCircle(Offset(w * 0.24, h * 0.68), w * 0.16, stroke);

    // Bánh trước
    canvas.drawCircle(Offset(w * 0.76, h * 0.68), w * 0.16, stroke);

    // Khung xe EV
    final frame = Path()
      ..moveTo(w * 0.24, h * 0.68)
      ..lineTo(w * 0.46, h * 0.52)
      ..lineTo(w * 0.66, h * 0.34)
      ..lineTo(w * 0.76, h * 0.68)
      ..moveTo(w * 0.46, h * 0.52)
      ..lineTo(w * 0.42, h * 0.38)
      ..lineTo(w * 0.32, h * 0.38) // Yên xe
      ..moveTo(w * 0.66, h * 0.34)
      ..lineTo(w * 0.60, h * 0.24); // Tay lái
    canvas.drawPath(frame, stroke);
  }
}

// -------------------------------------------------------------
// 8. Battery Painter
// -------------------------------------------------------------
class _BatteryPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.08);

    // Thân pin
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.28, w * 0.70, h * 0.44),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(body, stroke);

    // Cực dương
    final tip = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.84, h * 0.40, w * 0.06, h * 0.20),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(tip, createFill());

    // Các vạch pin bên trong
    final barW = w * 0.12;
    final barH = h * 0.26;
    for (int i = 0; i < 3; i++) {
      final barRect = Rect.fromLTWH(
        w * 0.22 + i * (barW + w * 0.06),
        h * 0.37,
        barW,
        barH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, Radius.circular(w * 0.02)),
        createFill(),
      );
    }
  }
}

// -------------------------------------------------------------
// 9. Speedometer Painter
// -------------------------------------------------------------
class _SpeedometerPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Cung tốc độ
    final arcRect = Rect.fromCircle(
      center: Offset(w * 0.5, h * 0.54),
      radius: w * 0.38,
    );
    canvas.drawArc(arcRect, math.pi * 0.75, math.pi * 1.5, false, stroke);

    // Kim đồng hồ
    final needle = Path()
      ..moveTo(w * 0.5, h * 0.54)
      ..lineTo(w * 0.68, h * 0.34);
    canvas.drawPath(needle, stroke);

    // Chốt tâm kim
    canvas.drawCircle(Offset(w * 0.5, h * 0.54), w * 0.06, createFill());
  }
}

// -------------------------------------------------------------
// 10. Shield Painter (An toàn / Chống trộm)
// -------------------------------------------------------------
class _ShieldPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Vành khiên
    final shield = Path()
      ..moveTo(w * 0.5, h * 0.10)
      ..lineTo(w * 0.84, h * 0.24)
      ..quadraticBezierTo(w * 0.84, h * 0.62, w * 0.5, h * 0.90)
      ..quadraticBezierTo(w * 0.16, h * 0.62, w * 0.16, h * 0.24)
      ..close();
    canvas.drawPath(shield, stroke);

    // Dấu check an toàn
    final check = Path()
      ..moveTo(w * 0.36, h * 0.48)
      ..lineTo(w * 0.46, h * 0.58)
      ..lineTo(w * 0.64, h * 0.38);
    canvas.drawPath(check, stroke);
  }
}

// -------------------------------------------------------------
// 11. NFC Painter
// -------------------------------------------------------------
class _NfcPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Khung thẻ chữ nhật bo góc
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.18, w * 0.76, h * 0.64),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(card, stroke);

    // 3 sóng tiếp xúc NFC
    for (int i = 1; i <= 3; i++) {
      final r = w * (0.08 + i * 0.09);
      final wave = Path()
        ..addArc(
          Rect.fromCircle(center: Offset(w * 0.35, h * 0.50), radius: r),
          -math.pi * 0.35,
          math.pi * 0.70,
        );
      canvas.drawPath(wave, createStroke(w * 0.07));
    }
  }
}

// -------------------------------------------------------------
// 12. Settings Painter (Thanh trượt EV)
// -------------------------------------------------------------
class _SettingsPainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);
    final fill = createFill();

    // Track 1
    canvas.drawLine(Offset(w * 0.14, h * 0.34), Offset(w * 0.86, h * 0.34), stroke);
    canvas.drawCircle(Offset(w * 0.38, h * 0.34), w * 0.09, fill);

    // Track 2
    canvas.drawLine(Offset(w * 0.14, h * 0.66), Offset(w * 0.86, h * 0.66), stroke);
    canvas.drawCircle(Offset(w * 0.62, h * 0.66), w * 0.09, fill);
  }
}

// -------------------------------------------------------------
// 13. Profile Painter
// -------------------------------------------------------------
class _ProfilePainter extends _BaseGeelyPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = createStroke(w * 0.085);

    // Đầu
    canvas.drawCircle(Offset(w * 0.5, h * 0.34), w * 0.18, stroke);

    // Vai
    final body = Path()
      ..moveTo(w * 0.20, h * 0.82)
      ..quadraticBezierTo(w * 0.26, h * 0.60, w * 0.5, h * 0.60)
      ..quadraticBezierTo(w * 0.74, h * 0.60, w * 0.80, h * 0.82);
    canvas.drawPath(body, stroke);
  }
}
