import 'package:flutter/material.dart';

/// ✨ نظام التصميم الموحد لتطبيق نوافذ
/// Design Tokens — Premium / Professional / Compact

// ─────────────────────────────────────────────
//  BRAND COLORS
// ─────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Primary purple brand
  static const Color primary        = Color(0xFF60269E);
  static const Color primaryDark    = Color(0xFF4A1780);
  static const Color primaryLight   = Color(0xFF7B3FBF);
  static const Color primarySurface = Color(0xFFF4EEFF); // background tint

  // Accent
  static const Color accent         = Color(0xFFF1A559); // warm orange
  static const Color accentSurface  = Color(0xFFFFF3E6);

  // Teal (badges, verified)
  static const Color teal           = Color(0xFF0E7490);
  static const Color tealSurface    = Color(0xFFE0F5F9);

  // Semantic
  static const Color success        = Color(0xFF16A34A);
  static const Color successSurface = Color(0xFFDCFCE7);
  static const Color warning        = Color(0xFFD97706);
  static const Color warningSurface = Color(0xFFFEF3C7);
  static const Color error          = Color(0xFFDC2626);
  static const Color errorSurface   = Color(0xFFFEE2E2);
  static const Color info           = Color(0xFF2563EB);
  static const Color infoSurface    = Color(0xFFEFF6FF);

  // Neutral scale
  static const Color grey50         = Color(0xFFF9FAFB);
  static const Color grey100        = Color(0xFFF3F4F6);
  static const Color grey200        = Color(0xFFE5E7EB);
  static const Color grey300        = Color(0xFFD1D5DB);
  static const Color grey400        = Color(0xFF9CA3AF);
  static const Color grey500        = Color(0xFF6B7280);
  static const Color grey600        = Color(0xFF4B5563);
  static const Color grey700        = Color(0xFF374151);
  static const Color grey800        = Color(0xFF1F2937);
  static const Color grey900        = Color(0xFF111827);

  // Surface / Background
  static const Color surfaceLight   = Color(0xFFFFFFFF);
  static const Color bgLight        = Color(0xFFF8F7FC);
  static const Color cardLight      = Color(0xFFFFFFFF);
  static const Color borderLight    = Color(0xFFEDE9F5);

  static const Color surfaceDark    = Color(0xFF1A1625);
  static const Color bgDark         = Color(0xFF120F18);
  static const Color cardDark       = Color(0xFF221E2E);
  static const Color borderDark     = Color(0xFF2E2840);

  // ── Backward-compatibility aliases (legacy names → canonical tokens)
  static const Color deepPurple   = primary;
  static const Color accentOrange = accent;
  static const Color background   = bgLight;
  static const Color softBlue     = Color(0xFF0E1216); // dark navy overlay
}

// ─────────────────────────────────────────────
//  TYPOGRAPHY SCALE  (compact, professional)
// ─────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  // Display
  static const double display1 = 22.0; // Hero titles
  static const double display2 = 19.0; // Page titles

  // Headings
  static const double h1 = 17.0;
  static const double h2 = 15.0;
  static const double h3 = 13.5;

  // Body
  static const double bodyLg  = 13.0;
  static const double bodyMd  = 12.0;
  static const double bodySm  = 11.0;

  // Caption / Label
  static const double caption = 10.5;
  static const double micro   = 9.5;

  // Font weights
  static const FontWeight bold     = FontWeight.w700;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight medium   = FontWeight.w500;
  static const FontWeight regular  = FontWeight.w400;

  // ── Light mode text colors
  static const Color textPrimary   = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF52637A);
  static const Color textTertiary  = Color(0xFF94A3B8);
  static const Color textDisabled  = Color(0xFFCBD5E1);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Dark mode text colors
  static const Color textPrimaryDark   = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark  = Color(0xFF64748B);
  static const Color textDisabledDark  = Color(0xFF334155);
}

// ─────────────────────────────────────────────
//  SPACING SCALE  (8-point grid, compact)
// ─────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs  = 4.0;
  static const double sm  = 6.0;
  static const double md  = 8.0;
  static const double lg  = 12.0;
  static const double xl  = 16.0;
  static const double xxl = 20.0;
  static const double x3  = 24.0;

  // Insets
  static const EdgeInsets cardPadding      = EdgeInsets.all(12);
  static const EdgeInsets cardPaddingSnug  = EdgeInsets.all(10);
  static const EdgeInsets screenPadding    = EdgeInsets.symmetric(horizontal: 14);
  static const EdgeInsets listItemPadding  = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
}

// ─────────────────────────────────────────────
//  BORDER RADIUS
// ─────────────────────────────────────────────
class AppRadius {
  AppRadius._();

  static const double xs   = 6.0;
  static const double sm   = 10.0;
  static const double md   = 14.0;
  static const double lg   = 18.0;
  static const double xl   = 22.0;
  static const double xxl  = 28.0;
  static const double pill = 999.0;

  static const BorderRadius cardRadius    = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cardRadiusMd  = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardRadiusLg  = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillRadius    = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius btnRadius     = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius btnRadiusMd   = BorderRadius.all(Radius.circular(md));
}

// ─────────────────────────────────────────────
//  SHADOWS  (layered, subtle)
// ─────────────────────────────────────────────
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      spreadRadius: 0,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 20,
      spreadRadius: -2,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 16,
      spreadRadius: 0,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> topBar = [
    BoxShadow(
      color: Color(0x0C000000),
      blurRadius: 12,
      spreadRadius: 0,
      offset: Offset(0, 2),
    ),
  ];

  static List<BoxShadow> primaryGlow(Color color) => [
    BoxShadow(
      color: color.withAlpha(40),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────
//  DURATIONS
// ─────────────────────────────────────────────
class AppDurations {
  AppDurations._();

  static const Duration fast   = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow   = Duration(milliseconds: 350);
}

// ─────────────────────────────────────────────
//  THEME BUILDERS
// ─────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light => _buildTheme(isDark: false);
  static ThemeData get dark  => _buildTheme(isDark: true);

  static ThemeData _buildTheme({required bool isDark}) {
    final Color seedColor     = AppColors.primary;
    final Color bg            = isDark ? AppColors.bgDark  : AppColors.bgLight;
    final Color surface       = isDark ? AppColors.cardDark : AppColors.cardLight;
    final Color textPrimary   = isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary;
    final Color textSecondary = isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      fontFamily: 'Cairo',
      useMaterial3: true,
      scaffoldBackgroundColor: bg,

      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: surface,
      ),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.surfaceLight,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        iconTheme: IconThemeData(color: textSecondary, size: 20),
        actionsIconTheme: IconThemeData(color: textSecondary, size: 20),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        margin: EdgeInsets.zero,
      ),

      // Chip
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(
          fontSize: AppTextStyles.bodySm,
          fontWeight: AppTextStyles.medium,
          color: textSecondary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: const StadiumBorder(),
        side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.borderDark : AppColors.borderLight,
        thickness: 0.5,
        space: 0,
      ),

      // Text
      textTheme: TextTheme(
        // Display
        displayLarge: TextStyle(fontSize: AppTextStyles.display1, fontWeight: AppTextStyles.bold, color: textPrimary),
        displayMedium: TextStyle(fontSize: AppTextStyles.display2, fontWeight: AppTextStyles.bold, color: textPrimary),
        // Headline
        headlineLarge: TextStyle(fontSize: AppTextStyles.h1, fontWeight: AppTextStyles.semiBold, color: textPrimary),
        headlineMedium: TextStyle(fontSize: AppTextStyles.h2, fontWeight: AppTextStyles.semiBold, color: textPrimary),
        headlineSmall: TextStyle(fontSize: AppTextStyles.h3, fontWeight: AppTextStyles.semiBold, color: textPrimary),
        // Body
        bodyLarge: TextStyle(fontSize: AppTextStyles.bodyLg, fontWeight: AppTextStyles.regular, color: textPrimary),
        bodyMedium: TextStyle(fontSize: AppTextStyles.bodyMd, fontWeight: AppTextStyles.regular, color: textSecondary),
        bodySmall: TextStyle(fontSize: AppTextStyles.bodySm, fontWeight: AppTextStyles.regular, color: textSecondary),
        // Label
        labelLarge: TextStyle(fontSize: AppTextStyles.bodyLg, fontWeight: AppTextStyles.medium, color: textPrimary),
        labelMedium: TextStyle(fontSize: AppTextStyles.bodyMd, fontWeight: AppTextStyles.medium, color: textSecondary),
        labelSmall: TextStyle(fontSize: AppTextStyles.caption, fontWeight: AppTextStyles.medium, color: textSecondary),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.cardDark : AppColors.grey50,
        border: OutlineInputBorder(
          borderRadius: AppRadius.btnRadiusMd,
          borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.grey200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.btnRadiusMd,
          borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.grey200, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.btnRadiusMd,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        hintStyle: TextStyle(fontSize: AppTextStyles.bodyMd, color: textSecondary),
        labelStyle: TextStyle(fontSize: AppTextStyles.bodyMd, color: textSecondary),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.btnRadiusMd),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTextStyles.bodyLg,
            fontWeight: AppTextStyles.semiBold,
          ),
        ),
      ),

      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.btnRadiusMd),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTextStyles.bodyLg,
            fontWeight: AppTextStyles.semiBold,
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTextStyles.bodyLg,
            fontWeight: AppTextStyles.semiBold,
          ),
        ),
      ),

      // List Tile
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.bodyLg,
          fontWeight: AppTextStyles.medium,
          color: textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.bodyMd,
          color: textSecondary,
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadiusMd),
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.h2,
          fontWeight: AppTextStyles.semiBold,
          color: textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.bodyMd,
          color: textSecondary,
        ),
      ),

      // Bottom Sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        elevation: 0,
      ),

      // Icon
      iconTheme: IconThemeData(color: textSecondary, size: 20),

      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 60,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTextStyles.caption,
            fontWeight: AppTextStyles.semiBold,
          ),
        ),
      ),
    );
  }
}
