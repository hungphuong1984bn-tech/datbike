// Logo THBIKE dùng chung (splash, giới thiệu, ...). Dùng đúng tệp icon của ứng dụng
// để biểu tượng trong app luôn khớp với biểu tượng trên màn hình điện thoại.

import 'package:flutter/material.dart';

class ThBikeLogo extends StatelessWidget {
  final double size;
  final bool glow;
  const ThBikeLogo({super.key, this.size = 96, this.glow = true});

  @override
  Widget build(BuildContext context) {
    final r = size * 0.22;
    return Semantics(
      label: 'Logo THBIKE',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: const Color(0xFF1FA2FF).withValues(alpha: 0.45),
                    blurRadius: size * 0.30,
                    spreadRadius: size * 0.01,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Image.asset(
            'assets/icon/icon.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF0B0F17),
              alignment: Alignment.center,
              child: Text('TH',
                  style: TextStyle(
                      color: const Color(0xFF39B8FF),
                      fontWeight: FontWeight.w900,
                      fontSize: size * 0.4)),
            ),
          ),
        ),
      ),
    );
  }
}
