import 'package:flutter/material.dart';

/// SDG green palette used across the prototype screens.
///
/// `primary`/`primaryDark`/`primaryLight`/`primaryAccent` are the original
/// names and stay put — 20+ screens across every module already reference
/// them directly. `primaryGreen`/`darkGreen`/`lightGreenFill`/`midGreen` are
/// the same four values under the shared-widget spec's names; new code
/// should prefer those, but both point at one literal each, so there is
/// never a risk of the two sets drifting apart.
///
/// These are brand accents. For text and surfaces that must flip between
/// light and dark mode, read `Theme.of(context).colorScheme` roles instead
/// of these literals — a fixed dark-green heading is invisible on a dark
/// background.
class AppColors {
  static const primary = Color(0xFF16794F);
  static const primaryDark = Color(0xFF0E4030);
  static const primaryLight = Color(0xFFE9F3EE);
  static const primaryAccent = Color(0xFFA3D0BB);

  static const primaryGreen = primary;
  static const darkGreen = primaryDark;
  static const lightGreenFill = primaryLight;
  static const midGreen = primaryAccent;
}

/// Shared spacing scale — use these instead of ad hoc SizedBox/padding
/// numbers so gaps stay consistent across modules.
class AppSpacing {
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
}

/// Card look shared by every module's cardTheme, pulled out so the values
/// are named instead of buried as literals inside [AppTheme.light].
class AppCardStyle {
  static const borderRadius = 14.0;
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

    // The green stays the brand accent in both modes, but in dark mode the
    // usable "primary" is the lighter accent green so it reads on a dark
    // surface; the deep green becomes a container fill instead.
    final colorScheme = isDark
        ? seeded.copyWith(
            primary: AppColors.primaryAccent,
            onPrimary: AppColors.primaryDark,
            primaryContainer: AppColors.primaryDark,
            onPrimaryContainer: AppColors.primaryLight,
            secondary: AppColors.primaryAccent,
            onSecondary: AppColors.primaryDark,
            secondaryContainer: AppColors.primaryDark,
            onSecondaryContainer: AppColors.primaryLight,
            tertiary: AppColors.primaryAccent,
          )
        : seeded.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            primaryContainer: AppColors.primaryLight,
            onPrimaryContainer: AppColors.primaryDark,
            secondary: AppColors.primaryDark,
            onSecondary: Colors.white,
            secondaryContainer: AppColors.primaryAccent,
            onSecondaryContainer: AppColors.primaryDark,
            // Pinned so ColorScheme.fromSeed never auto-generates a stray
            // blue-cyan tertiary — every screen that reads scheme.tertiary
            // (e.g. the stock dashboard's "Overstocked" label) stays
            // on-palette.
            tertiary: AppColors.primaryDark,
            onTertiary: Colors.white,
            tertiaryContainer: AppColors.primaryLight,
            onTertiaryContainer: AppColors.primaryDark,
            surface: Colors.white,
          );

    final cardColor = isDark ? colorScheme.surfaceContainerHigh : Colors.white;
    final fieldFill = isDark
        ? colorScheme.surfaceContainerHighest
        : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      // The app bar keeps the brand green in both modes.
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
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
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
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
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primaryContainer,
        circularTrackColor: colorScheme.primaryContainer,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        filled: true,
        fillColor: fieldFill,
      ),
    );
  }
}
