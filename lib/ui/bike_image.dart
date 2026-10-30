// Ảnh xe: ưu tiên ảnh THẬT do người dùng bổ sung (assets/images/real/), nếu
// chưa có thì dùng ảnh minh họa cũ và gắn nhãn rõ "ẢNH MINH HỌA".

import 'package:flutter/material.dart';

class BikeImage extends StatelessWidget {
  static const String realJpg = 'assets/images/real/quantum_s1.jpg';
  static const String realPng = 'assets/images/real/quantum_s1.png';
  static const String illustration = 'assets/images/bike_hero_3d.jpg';

  final BoxFit fit;
  const BikeImage({super.key, this.fit = BoxFit.contain});

  Widget _illustration() => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            illustration,
            fit: fit,
            errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.two_wheeler_rounded, size: 90)),
          ),
          Positioned(
            right: 10,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('ẢNH MINH HỌA',
                  key: Key('bike_image_illustration_label'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.asset(
        realJpg,
        fit: fit,
        errorBuilder: (_, _, _) => Image.asset(
          realPng,
          fit: fit,
          errorBuilder: (_, _, _) => _illustration(),
        ),
      ),
    );
  }
}
