// Theme "Kinetic Stitch EV" — hệ thống thiết kế dùng chung, hỗ trợ Dark/Light.
//
// Kiến trúc màu:
//  • [AppPalette]  — bảng màu bất biến cho từng chế độ (light / dark).
//  • [AppColors]   — API cũ giữ nguyên tên (AppColors.panel, .textDim, …) nhưng
//                    các màu phụ thuộc chế độ nay là getter đọc từ palette đang
//                    áp dụng. Màu thương hiệu/ngữ nghĩa cố định vẫn là const.
//  • Gốc app (main.dart) gọi AppColors.apply(brightness) rồi ép dựng lại cây
//    widget khi đổi chế độ, nên các màn hình cũ đổi màu mà không mất state.
//
// Quy ước chọn màu:
//  • primary      — chữ/icon nhấn (sáng hơn ở Dark để đủ tương phản).
//  • primaryFill  — nền nút đặc có chữ trắng (luôn #2563EB).
//  • error        — chữ/icon lỗi;  errorFill — nền nút nguy hiểm có chữ trắng.
//  • textPrimary / textDim / textSecondary / textMuted — 4 bậc chữ.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens dùng chung: khoảng cách, bo góc, vùng chạm, chuyển động.
// ─────────────────────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;

  /// Lề ngang chuẩn của mọi trang.
  static const double pageH = 20;
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 9999;
}

class AppSizes {
  AppSizes._();

  /// Vùng chạm tối thiểu (Material: 48dp). Dùng cho mọi nút/hàng bấm được.
  static const double minTap = 48;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double navBarHeight = 68;
}

class AppMotion {
  AppMotion._();
  // Nhẹ và ngắn: không gây lag / tốn pin.
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bảng màu theo chế độ
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class AppPalette {
  final Brightness brightness;

  // Nền & bề mặt
  final Color bg;
  final Color panel;
  final Color panelSecondary;
  final Color panelBorder;
  final Color panelBorderBright;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  // Chữ (4 bậc)
  final Color textPrimary;
  final Color textDim;
  final Color textSecondary;
  final Color textMuted;

  // Nhấn
  final Color primary;
  final Color accent;
  final Color primarySoft;
  final Color primarySoftBorder;

  // Ngữ nghĩa
  final Color error;
  final Color redSoft;
  final Color redSoftBorder;
  final Color redText;
  final Color greenSoft;
  final Color greenSoftBorder;
  final Color greenText;
  final Color amberSoft;
  final Color amberSoftBorder;
  final Color amberText;

  // Bóng đổ
  final Color shadow;
  final double shadowOpacityScale;

  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.panel,
    required this.panelSecondary,
    required this.panelBorder,
    required this.panelBorderBright,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.textPrimary,
    required this.textDim,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.accent,
    required this.primarySoft,
    required this.primarySoftBorder,
    required this.error,
    required this.redSoft,
    required this.redSoftBorder,
    required this.redText,
    required this.greenSoft,
    required this.greenSoftBorder,
    required this.greenText,
    required this.amberSoft,
    required this.amberSoftBorder,
    required this.amberText,
    required this.shadow,
    required this.shadowOpacityScale,
  });

  bool get isDark => brightness == Brightness.dark;

  /// Giao diện sáng — giữ nguyên diện mạo hiện tại của app.
  static const light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF8F9FA),
    panel: Color(0xFFFFFFFF),
    panelSecondary: Color(0xFFF8FAFC),
    panelBorder: Color(0xFFF1F5F9),
    panelBorderBright: Color(0xFFE2E8F0),
    surfaceContainer: Color(0xFFF1F5F9),
    surfaceContainerHigh: Color(0xFFE2E8F0),
    surfaceContainerHighest: Color(0xFFCBD5E1),
    textPrimary: Color(0xFF0F172A),
    textDim: Color(0xFF475569),
    textSecondary: Color(0xFF64748B),
    // #6B7A90 trên nền trắng ≈ 4.4:1 (cũ #94A3B8 chỉ ≈ 2.6:1 — khó đọc ngoài trời).
    textMuted: Color(0xFF6B7A90),
    primary: Color(0xFF2563EB),
    accent: Color(0xFF0284C7),
    primarySoft: Color(0xFFEFF6FF),
    primarySoftBorder: Color(0xFFBFDBFE),
    error: Color(0xFFBA1A1A),
    redSoft: Color(0xFFFEF2F2),
    redSoftBorder: Color(0xFFFECACA),
    redText: Color(0xFFDC2626),
    greenSoft: Color(0xFFF0FDF4),
    greenSoftBorder: Color(0xFFBBF7D0),
    greenText: Color(0xFF15803D),
    amberSoft: Color(0xFFFEF3C7),
    amberSoftBorder: Color(0xFFFDE68A),
    amberText: Color(0xFFB45309),
    shadow: Color(0xFF0F172A),
    shadowOpacityScale: 1.0,
  );

  /// Giao diện tối — nền graphite/navy, nhấn xanh điện/cyan.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0F17),
    panel: Color(0xFF131A26),
    panelSecondary: Color(0xFF0F1520),
    panelBorder: Color(0xFF1F2A3B),
    panelBorderBright: Color(0xFF2A3649),
    surfaceContainer: Color(0xFF1A2231),
    surfaceContainerHigh: Color(0xFF232E40),
    surfaceContainerHighest: Color(0xFF2F3C52),
    textPrimary: Color(0xFFE8EDF5),
    textDim: Color(0xFFB4BFCF),
    textSecondary: Color(0xFF97A5B9),
    textMuted: Color(0xFF7D8BA1),
    primary: Color(0xFF5B9BFF),
    accent: Color(0xFF38BDF8),
    primarySoft: Color(0xFF14233D),
    primarySoftBorder: Color(0xFF26426E),
    error: Color(0xFFFF7B7B),
    redSoft: Color(0xFF2B1518),
    redSoftBorder: Color(0xFF5A2429),
    redText: Color(0xFFFF8A8A),
    greenSoft: Color(0xFF11271D),
    greenSoftBorder: Color(0xFF1F4B34),
    greenText: Color(0xFF4ADE80),
    amberSoft: Color(0xFF2B2210),
    amberSoftBorder: Color(0xFF564214),
    amberText: Color(0xFFFBBF24),
    shadow: Color(0xFF000000),
    shadowOpacityScale: 4.0,
  );
}

class AppColors {
  AppColors._();

  static AppPalette _p = AppPalette.light;

  /// Palette đang áp dụng (chỉ gốc app gọi [apply]).
  static AppPalette get palette => _p;
  static bool get isDark => _p.isDark;

  /// Áp dụng palette theo độ sáng. Trả về true nếu có thay đổi.
  static bool apply(Brightness b) {
    final next = b == Brightness.dark ? AppPalette.dark : AppPalette.light;
    if (identical(next, _p)) return false;
    _p = next;
    return true;
  }

  // ── Bề mặt (phụ thuộc chế độ) ──────────────────────────────────────────────
  static Color get surface => _p.bg;
  static Color get surfaceDim => _p.panelBorderBright;
  static Color get surfaceBright => _p.bg;
  static Color get surfaceContainerLowest => _p.panel;
  static Color get surfaceContainerLow => _p.panelSecondary;
  static Color get surfaceContainer => _p.surfaceContainer;
  static Color get surfaceContainerHigh => _p.surfaceContainerHigh;
  static Color get surfaceContainerHighest => _p.surfaceContainerHighest;
  static Color get surfaceVariant => _p.surfaceContainer;

  static Color get bg => _p.bg;
  static Color get panel => _p.panel;
  static Color get panelSecondary => _p.panelSecondary;
  static Color get panelBorder => _p.panelBorder;
  static Color get panelBorderBright => _p.panelBorderBright;
  static Color get borderSubtle => _p.panelBorder;

  // ── Chữ ────────────────────────────────────────────────────────────────────
  static Color get onSurface => _p.textPrimary;
  static Color get onSurfaceVariant => _p.textDim;
  static Color get textPrimary => _p.textPrimary;
  static Color get textDim => _p.textDim;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;

  // ── Nhấn ───────────────────────────────────────────────────────────────────
  static Color get primary => _p.primary;
  static Color get accent => _p.accent;
  static Color get accentDim => _p.isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
  static Color get primarySoft => _p.primarySoft;
  static Color get primarySoftBorder => _p.primarySoftBorder;

  /// Nền nút đặc có chữ trắng — cố định ở cả hai chế độ (tương phản 5.2:1).
  static const primaryFill = Color(0xFF2563EB);
  static const primaryContainer = Color(0xFF1D4ED8);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onPrimaryContainer = Color(0xFFFDFCFF);

  static const secondary = Color(0xFF0EA5E9);
  static const secondaryContainer = Color(0xFF39B8FD);
  static const onSecondary = Color(0xFFFFFFFF);
  static const onSecondaryContainer = Color(0xFF004666);

  static const tertiary = Color(0xFF10B981); // Eco / sạc tối ưu / sức khỏe pin
  static const tertiaryContainer = Color(0xFF00855B);
  static const onTertiary = Color(0xFFFFFFFF);
  static const onTertiaryContainer = Color(0xFFF5FFF6);

  static const cyan = Color(0xFF0EA5E9);
  static const mint = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);

  // ── Trạng thái ─────────────────────────────────────────────────────────────
  static Color get error => _p.error;

  /// Nền nút nguy hiểm có chữ trắng.
  static const errorFill = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  static Color get redSoft => _p.redSoft;
  static Color get redSoftBorder => _p.redSoftBorder;
  static Color get redText => _p.redText;
  static Color get greenSoft => _p.greenSoft;
  static Color get greenSoftBorder => _p.greenSoftBorder;
  static Color get greenText => _p.greenText;
  static Color get amberSoft => _p.amberSoft;
  static Color get amberSoftBorder => _p.amberSoftBorder;
  static Color get amberText => _p.amberText;

  /// Biến thể của màu ngữ nghĩa dùng làm CHỮ/ICON nhỏ trên nền nhạt cùng màu
  /// (vd. amber #F59E0B làm chữ trên nền trắng chỉ ≈2:1 — không đọc được ngoài trời).
  static Color readable(Color c) {
    if (c == amber) return amberText;
    if (c == red || c == errorFill || c == _p.error) return redText;
    if (c == tertiary || c == mint) return greenText;
    if (c == cyan || c == secondary) return accent;
    return c;
  }

  // ── Bóng đổ (Dark: đậm hơn vì nền tối nuốt bóng nhẹ) ───────────────────────
  static Color _shadow(double a) =>
      _p.shadow.withValues(alpha: (a * _p.shadowOpacityScale).clamp(0.0, 1.0));

  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: _shadow(0.024), blurRadius: 16, offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> get modalShadow => [
        BoxShadow(color: _shadow(0.06), blurRadius: 32, offset: const Offset(0, 12)),
        BoxShadow(color: _shadow(0.03), blurRadius: 6, offset: const Offset(0, 2)),
      ];

  static BoxShadow get activeHalo => BoxShadow(
        color: const Color(0xFF0EA5E9).withValues(alpha: _p.isDark ? 0.28 : 0.18),
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

  static ThemeData light() => _build(AppPalette.light);
  static ThemeData dark() => _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final isDark = p.isDark;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final baseText = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    final scheme = (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: p.primary,
      onPrimary: isDark ? const Color(0xFF06142E) : AppColors.onPrimary,
      primaryContainer: isDark ? p.primarySoft : AppColors.primaryContainer,
      onPrimaryContainer: isDark ? p.primary : AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: isDark ? p.surfaceContainerHigh : AppColors.secondaryContainer,
      onSecondaryContainer: isDark ? p.textPrimary : AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      surface: p.panel,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textDim,
      surfaceContainerLowest: p.panel,
      surfaceContainerLow: p.panelSecondary,
      surfaceContainer: p.surfaceContainer,
      surfaceContainerHigh: p.surfaceContainerHigh,
      surfaceContainerHighest: p.surfaceContainerHighest,
      outline: p.panelBorderBright,
      outlineVariant: p.panelBorder,
      error: p.error,
      onError: isDark ? const Color(0xFF3B0A0A) : AppColors.onError,
    );

    TextStyle jakarta(double size, FontWeight w, Color c, {double? ls}) =>
        GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c, letterSpacing: ls);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      splashFactory: InkRipple.splashFactory,
      textTheme: baseText.copyWith(
        displayLarge: AppTypography.displayLgMobile(color: p.textPrimary),
        headlineLarge: AppTypography.headlineXlMobile(color: p.textPrimary),
        headlineMedium: AppTypography.headlineMd(color: p.textPrimary),
        headlineSmall: AppTypography.headlineSm(color: p.textPrimary),
        bodyLarge: AppTypography.bodyLg(color: p.textPrimary),
        bodyMedium: AppTypography.bodyMd(color: p.textPrimary),
        bodySmall: AppTypography.bodySm(color: p.textDim),
        labelLarge: AppTypography.labelLg(color: p.textPrimary),
        labelMedium: AppTypography.labelMd(color: p.textDim),
        labelSmall: AppTypography.labelSm(color: p.textDim),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: p.textPrimary, size: 20),
        actionsIconTheme: IconThemeData(color: p.textPrimary, size: 22),
        titleTextStyle: jakarta(18, FontWeight.w700, p.textPrimary, ls: -0.3),
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: p.panelBorder, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.panelBorder, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        contentTextStyle: jakarta(14, FontWeight.w400, p.textDim),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.panel,
        showDragHandle: true,
        dragHandleColor: p.panelBorderBright,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: jakarta(14, FontWeight.w500, p.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panelSecondary,
        hintStyle: jakarta(14, FontWeight.w400, p.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.panelBorderBright),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.panelBorderBright),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textDim,
        textColor: p.textPrimary,
        minVerticalPadding: 8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: AppSizes.navBarHeight,
        indicatorColor: p.primary.withValues(alpha: isDark ? 0.20 : 0.12),
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => jakarta(
            11.5,
            s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            s.contains(WidgetState.selected) ? p.primary : p.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? p.primary : p.textSecondary,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryFill,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: p.surfaceContainerHigh,
          disabledForegroundColor: p.textMuted,
          textStyle: jakarta(14, FontWeight.w600, Colors.white, ls: 0.2),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(AppSizes.minTap),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          backgroundColor: p.panel,
          side: BorderSide(color: p.panelBorderBright, width: 1),
          textStyle: jakarta(14, FontWeight.w600, p.textPrimary),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(AppSizes.minTap),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          minimumSize: const Size(AppSizes.minTap, AppSizes.minTap),
          textStyle: jakarta(14, FontWeight.w600, p.primary),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? p.surfaceContainerHigh : const Color(0xFF131B2E),
        contentTextStyle: jakarta(13, FontWeight.w500, isDark ? p.textPrimary : Colors.white),
        actionTextColor: isDark ? p.primary : const Color(0xFF93C5FD),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primaryFill : p.surfaceContainer,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : p.panelBorderBright,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.panelSecondary,
        side: BorderSide(color: p.panelBorderBright),
        labelStyle: jakarta(12.5, FontWeight.w600, p.textDim),
        shape: const StadiumBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceContainer,
        circularTrackColor: p.surfaceContainer,
      ),
    );
  }
}
