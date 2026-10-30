// Design System v3 — token bổ sung: gradient, ánh sáng (glow), mức độ nghiêm trọng.
// Chỉ THÊM, không thay đổi AppColors/AppPalette hiện có (các màn cũ không bị ảnh hưởng).

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Mức độ nghiêm trọng dùng chung cho cảnh báo / lỗi / trạng thái cell.
enum Severity { ok, info, warning, critical }

extension SeverityX on Severity {
  String get label {
    switch (this) {
      case Severity.ok:
        return 'Bình thường';
      case Severity.info:
        return 'Thông tin';
      case Severity.warning:
        return 'Cảnh báo';
      case Severity.critical:
        return 'Nghiêm trọng';
    }
  }

  IconData get icon {
    switch (this) {
      case Severity.ok:
        return Icons.check_circle_rounded;
      case Severity.info:
        return Icons.info_rounded;
      case Severity.warning:
        return Icons.warning_amber_rounded;
      case Severity.critical:
        return Icons.error_rounded;
    }
  }

  /// Màu nền/nhấn (không dùng làm chữ nhỏ — dùng [AppColors.readable]).
  Color get color {
    switch (this) {
      case Severity.ok:
        return AppColors.tertiary;
      case Severity.info:
        return AppColors.cyan;
      case Severity.warning:
        return AppColors.amber;
      case Severity.critical:
        return AppColors.red;
    }
  }
}

class AppGradients {
  AppGradients._();

  /// Nền trang: chuyển nhẹ từ bg sang panelSecondary, có vệt sáng xanh rất nhẹ ở trên.
  static LinearGradient get page => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(
            AppColors.primary.withValues(alpha: AppColors.isDark ? 0.10 : 0.05),
            AppColors.bg,
          ),
          AppColors.bg,
        ],
        stops: const [0.0, 0.55],
      );

  /// Thẻ nổi bật (hero): hai lớp xanh điện → cyan, dùng nhẹ tay.
  static LinearGradient get hero => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: AppColors.isDark
            ? const [Color(0xFF16253F), Color(0xFF0F1B2E)]
            : const [Color(0xFFEAF2FF), Color(0xFFF4F9FF)],
      );

  /// Thanh năng lượng (sạc/pin).
  static LinearGradient energy(Color base) => LinearGradient(
        colors: [base.withValues(alpha: 0.75), base],
      );
}

class AppGlow {
  AppGlow._();

  /// Quầng sáng mềm quanh phần tử đang hoạt động. [intensity] 0..1.
  static List<BoxShadow> soft(Color c, {double intensity = 1}) => [
        BoxShadow(
          color: c.withValues(
            alpha: ((AppColors.isDark ? 0.35 : 0.20) * intensity).clamp(0.0, 1.0),
          ),
          blurRadius: 18,
          spreadRadius: 0,
        ),
      ];
}
