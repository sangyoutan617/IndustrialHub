import 'package:flutter/material.dart';

/// SDG green palette used across the prototype screens.
///
/// `primary`/`primaryDark`/`primaryLight`/`primaryAccent` are the original
/// names and stay put — 20+ screens across every module already reference
/// them directly. `primaryGreen`/`darkGreen`/`lightGreenFill`/`midGreen` are
/// the same four values under the shared-widget spec's names; new code
/// should prefer those, but both point at one literal each, so there is
/// never a risk of the two sets drifting apart.
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
  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
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
          // (e.g. the stock dashboard's "Overstocked" label) stays on-palette.
          tertiary: AppColors.primaryDark,
          onTertiary: Colors.white,
          tertiaryContainer: AppColors.primaryLight,
          onTertiaryContainer: AppColors.primaryDark,
          surface: Colors.white,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: AppCardStyle.elevation,
        margin: AppCardStyle.margin,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppCardStyle.borderRadius),
          side: BorderSide(color: Colors.grey.shade200),
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
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryLight,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            color: selected ? AppColors.primaryDark : Colors.grey.shade600,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primaryDark : Colors.grey.shade600,
          );
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primaryLight,
        circularTrackColor: AppColors.primaryLight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryLight,
        labelStyle: const TextStyle(color: AppColors.primaryDark),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
