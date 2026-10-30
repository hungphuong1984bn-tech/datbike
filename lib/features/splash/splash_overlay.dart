// Splash THBIKE trong Flutter: nối tiếp màn khởi động native (nền đen + logo) rồi
// mờ dần để lộ ứng dụng. Chỉ là lớp phủ hiển thị ~1,3 giây — không chặn khởi tạo,
// không dùng Timer (dùng AnimationController nên dọn sạch khi dispose/test).

import 'package:flutter/material.dart';

import '../../core/brand/app_info.dart';
import '../../ui/brand_logo.dart';

class ThBikeSplashOverlay extends StatefulWidget {
  final Widget child;
  const ThBikeSplashOverlay({super.key, required this.child});

  @override
  State<ThBikeSplashOverlay> createState() => _ThBikeSplashOverlayState();
}

class _ThBikeSplashOverlayState extends State<ThBikeSplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 65),
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35),
  ]).animate(_c);
  late final Animation<double> _logoScale = Tween(begin: 0.88, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.35, curve: Curves.easeOutBack)));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Giữ nguyên cấu trúc Stack sau khi splash xong để Navigator KHÔNG bị dựng lại.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_done)
        IgnorePointer(
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF05070B), Color(0xFF0B1220)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 5),
                    ScaleTransition(scale: _logoScale, child: const ThBikeLogo(size: 132)),
                    const SizedBox(height: 28),
                    const Text(
                      kAppName,
                      style: TextStyle(
                        color: Color(0xFFF2F6FA),
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      kAppTagline,
                      style: TextStyle(
                        color: Color(0xFF8FA3B8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(flex: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Text(
                        'v$kAppVersion  •  $kDeveloperName',
                        style: TextStyle(
                          color: Color(0xFF5E7186),
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
