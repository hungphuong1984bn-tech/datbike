// Theme "Kinetic Stitch EV" — Thiết kế giao diện xe điện thế hệ mới.
// Nền sáng tinh khôi (Luminous Canvas #FAF8FF), thẻ trắng nguyên bản (#FFFFFF) viền hairline mảnh (#E2E8F0),
// tương phản sâu (Deep Slate #0F172A), accent xanh điện (Electric Azure #0284C7 & Cyan #0EA5E9),
// kết hợp Space Grotesk (chỉ số & telemetry) và Plus Jakarta Sans (nội dung & điều khiển).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Surface System (EV Companion Clean Aesthetic)
  static const surface = Color(0xFFF8F9FA);
  static const surfaceDim = Color(0xFFE2E8F0);
  static const surfaceBright = Color(0xFFF8F9FA);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF8FAFC);
  static const surfaceContainer = Color(0xFFF1F5F9);
  static const surfaceContainerHigh = Color(0xFFE2E8F0);
  static const surfaceContainerHighest = Color(0xFFCBD5E1);
  static const surfaceVariant = Color(0xFFF1F5F9);

  // Background & Panels
  static const bg = Color(0xFFF8F9FA);
  static const panel = Color(0xFFFFFFFF);
  static const panelSecondary = Color(0xFFF8FAFC);
  static const panelBorder = Color(0xFFF1F5F9);
  static const panelBorderBright = Color(0xFFE2E8F0);
  static const borderSubtle = Color(0xFFF1F5F9);

  // Core Brand Colors
  static const primary = Color(0xFF2563EB); // Electric Azure Blue
  static const primaryContainer = Color(0xFF1D4ED8);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onPrimaryContainer = Color(0xFFFDFCFF);

  static const secondary = Color(0xFF0EA5E9); // Energy Hue Accent
  static const secondaryContainer = Color(0xFF39B8FD);
  static const onSecondary = Color(0xFFFFFFFF);
  static const onSecondaryContainer = Color(0xFF004666);

  static const tertiary = Color(0xFF10B981); // Eco / Optimal Charging / Battery Health
  static const tertiaryContainer = Color(0xFF00855B);
  static const onTertiary = Color(0xFFFFFFFF);
  static const onTertiaryContainer = Color(0xFFF5FFF6);

  // Neutral Core & Typography Contrast
  static const onSurface = Color(0xFF131B2E);
  static const onSurfaceVariant = Color(0xFF3F4850);
  static const textPrimary = Color(0xFF0F172A); // Deep Slate
  static const textDim = Color(0xFF475569);     // Muted Slate
  static const textMuted = Color(0xFF94A3B8);   // Disabled / Placeholder

  // Accents & Functional Colors
  static const accent = Color(0xFF0284C7);
  static const accentDim = Color(0xFF0369A1);
  static const cyan = Color(0xFF0EA5E9);
  static const mint = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);

  // Error States
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  // Shadow Definitions (Soft ambient light dissipation)
  static const cardShadow = [
    BoxShadow(
      color: Color(0x060F172A),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const modalShadow = [
    BoxShadow(
      color: Color(0x0F0F172A),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const activeHalo = BoxShadow(
    color: Color(0x2E0EA5E9),
    spreadRadius: 3,
    blurRadius: 0,
  );
}

class AppTypography {
  AppTypography._();

  // Space Grotesk & Syne EV Wide Typography (Headlines, Numbers & Telemetry)
  static TextStyle evWide({
    double fontSize = 32,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing ?? -0.5,
        height: height,
        color: color ?? AppColors.textPrimary,
      );

  static TextStyle displayLg({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 56,
        fontWeight: FontWeight.w600,
        height: 64 / 56,
        letterSpacing: -0.03 * 56,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle displayLgMobile({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 48 / 40,
        letterSpacing: -0.02 * 40,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle headlineXl({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        height: 44 / 36,
        letterSpacing: -0.02 * 36,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle headlineXlMobile({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 36 / 28,
        letterSpacing: -0.01 * 28,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle headlineMd({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        height: 32 / 24,
        letterSpacing: -0.01 * 24,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle headlineSm({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 28 / 20,
        letterSpacing: 0,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // Plus Jakarta Sans (Body & Controls)
  static TextStyle bodyLg({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 28 / 18,
        color: color ?? AppColors.textPrimary,
      );

  static TextStyle bodyMd({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 22 / 15,
        color: color ?? AppColors.textPrimary,
      );

  static TextStyle bodySm({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 18 / 13,
        color: color ?? AppColors.textDim,
      );

  static TextStyle labelLg({Color? color, FontWeight? fontWeight}) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: fontWeight ?? FontWeight.w600,
        height: 20 / 14,
        letterSpacing: 0.01 * 14,
        color: color ?? AppColors.textPrimary,
      );

  static TextStyle labelMd({Color? color, FontWeight? fontWeight}) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: fontWeight ?? FontWeight.w600,
        height: 16 / 12,
        letterSpacing: 0.04 * 12,
        color: color ?? AppColors.textDim,
      );

  static TextStyle labelSm({Color? color, FontWeight? fontWeight}) => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: fontWeight ?? FontWeight.w500,
        height: 14 / 11,
        letterSpacing: 0.06 * 11,
        color: color ?? AppColors.textDim,
      );
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final baseText = GoogleFonts.plusJakartaSansTextTheme();

    final scheme = const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      surface: AppColors.panel,
      onSurface: AppColors.textPrimary,
      error: AppColors.red,
      onError: AppColors.onError,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: baseText.copyWith(
        displayLarge: AppTypography.displayLgMobile(),
        headlineLarge: AppTypography.headlineXlMobile(),
        headlineMedium: AppTypography.headlineMd(),
        headlineSmall: AppTypography.headlineSm(),
        bodyLarge: AppTypography.bodyLg(),
        bodyMedium: AppTypography.bodyMd(),
        bodySmall: AppTypography.bodySm(),
        labelLarge: AppTypography.labelLg(),
        labelMedium: AppTypography.labelMd(),
        labelSmall: AppTypography.labelSm(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 20),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.panelBorder, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.panelBorder,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.panel,
        elevation: 0,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textDim,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textDim,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.panel,
          side: const BorderSide(color: AppColors.panelBorder, width: 1),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.onSurface,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textDim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.panelSecondary,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : AppColors.panelBorder,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.panelSecondary,
      ),
    );
  }

  // Alias cho tương thích code cũ
  static ThemeData dark() => light();
}
