import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF0F766E);
  static const primaryDark = Color(0xFF115E59);
  static const primaryLight = Color(0xFFCCFBF1);
  static const primaryAccent = Color(0xFF14B8A6);

  static const secondary = Color(0xFF475569);
  static const secondaryDark = Color(0xFF334155);
  static const secondaryLight = Color(0xFFE2E8F0);

  static const accent = Color(0xFF14B8A6);

  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);
  static const warning = Color(0xFFD97706);
  static const warningLight = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626);
  static const dangerLight = Color(0xFFFEE2E2);
  static const info = Color(0xFF0284C7);
  static const infoLight = Color(0xFFE0F2FE);

  static const neutral100 = background;
  static const neutral300 = border;
  static const neutral500 = textMuted;
  static const neutral700 = textSecondary;
}

class AppSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

class AppCardStyle {
  static const borderRadius = AppRadius.lg;
  static const elevation = 0.0;
  static const margin = EdgeInsets.zero;
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seeded = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );

    final colorScheme = isDark
        ? seeded.copyWith(
            primary: AppColors.primaryAccent,
            onPrimary: AppColors.primaryDark,
            primaryContainer: AppColors.primaryDark,
            onPrimaryContainer: AppColors.primaryLight,
            secondary: AppColors.secondaryLight,
            onSecondary: AppColors.secondaryDark,
            secondaryContainer: AppColors.secondaryDark,
            onSecondaryContainer: AppColors.secondaryLight,
            tertiary: AppColors.accent,
            error: const Color(0xFFE6867F),
          )
        : seeded.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            primaryContainer: AppColors.primaryLight,
            onPrimaryContainer: AppColors.primaryDark,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            secondaryContainer: AppColors.secondaryLight,
            onSecondaryContainer: AppColors.secondaryDark,
            tertiary: AppColors.accent,
            onTertiary: Colors.white,
            tertiaryContainer: AppColors.secondaryLight,
            onTertiaryContainer: AppColors.secondaryDark,
            error: AppColors.danger,
            errorContainer: AppColors.dangerLight,
            onErrorContainer: AppColors.danger,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            onSurfaceVariant: AppColors.textSecondary,
            outline: AppColors.border,
            outlineVariant: AppColors.border,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF6F8FA),
            surfaceContainer: const Color(0xFFEEF1F4),
            surfaceContainerHigh: const Color(0xFFE7ECF1),
            surfaceContainerHighest: const Color(0xFFE2E8F0),
          );

    final scaffoldBg = isDark ? colorScheme.surface : AppColors.background;
    final cardColor = isDark ? colorScheme.surfaceContainerHigh : Colors.white;
    final fieldFill = isDark
        ? colorScheme.surfaceContainerHighest
        : Colors.white;
    final baseTextTheme = ThemeData(brightness: brightness).textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: baseTextTheme.copyWith(
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: AppCardStyle.elevation,
        margin: AppCardStyle.margin,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppCardStyle.borderRadius),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            color: selected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primaryContainer,
        circularTrackColor: colorScheme.primaryContainer,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
