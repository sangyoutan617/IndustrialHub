import 'package:flutter/material.dart';

/// IndustrialHub's design system: color, spacing, radius and card tokens.
///
/// Everything else in the app should read colors via `Theme.of(context)`
/// (`colorScheme`, `textTheme`) rather than these constants directly — the
/// constants exist so [AppTheme] itself, and the handful of places that
/// genuinely need a brand literal (an icon badge, a chart line color), have
/// one place to draw from. Reading `Theme.of(context).colorScheme.primary`
/// instead of [AppColors.primary] is what keeps a widget correct in dark
/// mode, where the "usable primary" swaps to [AppColors.primaryAccent].
class AppColors {
  // ---- Brand — IndustrialHub teal, the app's exclusive identity color
  // (AppBar, primary buttons, active nav, selected states, links). Used
  // deliberately, not on every component — see AppTheme's neutral surface
  // roles for everything else. ----
  static const primary = Color(0xFF0F766E);
  static const primaryDark = Color(0xFF115E59);
  static const primaryLight = Color(0xFFCCFBF1);
  static const primaryAccent = Color(0xFF14B8A6);

  // ---- Secondary — a muted slate, deliberately NOT another teal, so
  // secondary emphasis (e.g. the capacity dashboard's "Labour" bar next to
  // the primary "Machine" bar) reads as a distinct, calmer accent instead
  // of doubling down on the brand color. ----
  static const secondary = Color(0xFF475569);
  static const secondaryDark = Color(0xFF334155);
  static const secondaryLight = Color(0xFFE2E8F0);

  // ---- Accent — the brighter teal reserved for standout calls-to-action
  // (FABs, "generate insight" sparkles) that need to read as actionable. ----
  static const accent = Color(0xFF14B8A6);

  // ---- Neutral surfaces/text — the slate scale used for page background,
  // card surfaces, and text hierarchy so the app reads as calm/professional
  // rather than colorful. ----
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  // ---- Semantic status colors — the single source of truth for status/risk
  // language app-wide (stock health, supply risk, order status, bottleneck
  // alerts). Each has a light "container" tint for pill/badge backgrounds.
  // Never assign status colors ad hoc per screen — always go through these
  // (see StatusChip in lib/widgets/status.dart). ----
  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);
  static const warning = Color(0xFFD97706);
  static const warningLight = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626);
  static const dangerLight = Color(0xFFFEE2E2);
  static const info = Color(0xFF0284C7);
  static const infoLight = Color(0xFFE0F2FE);

  // ---- Neutral scale — for borders, muted icons and secondary text that
  // need a fixed gray beyond what ColorScheme provides (prefer
  // colorScheme.onSurfaceVariant/outline when a theme-aware gray will do;
  // reach for these when a screen needs a literal outside that role).
  // Aligned to the same slate scale as background/border/text above. ----
  static const neutral100 = background;
  static const neutral300 = border;
  static const neutral500 = textMuted;
  static const neutral700 = textSecondary;
}

/// Shared spacing scale — use these instead of ad hoc SizedBox/padding
/// numbers so gaps stay consistent across modules.
class AppSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Shared corner-radius scale. `sm` for small chips/pills-adjacent controls,
/// `md` for inputs/buttons, `lg` for cards, `pill` for fully-rounded status
/// chips and badges.
class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// Card look shared by every module's cardTheme, pulled out so the values
/// are named instead of buried as literals inside [AppTheme.light].
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

    // Teal stays the brand identity in both modes, but in dark mode the
    // usable "primary" is the brighter accent teal so it reads on a dark
    // surface; the deep teal becomes a container fill instead.
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
            // Pinned so ColorScheme.fromSeed never auto-generates a stray
            // tertiary — every screen that reads scheme.tertiary (e.g. the
            // stock dashboard's "Overstocked" label) stays on-palette.
            tertiary: AppColors.accent,
            onTertiary: Colors.white,
            tertiaryContainer: AppColors.secondaryLight,
            onTertiaryContainer: AppColors.secondaryDark,
            error: AppColors.danger,
            errorContainer: AppColors.dangerLight,
            onErrorContainer: AppColors.danger,
            // Exact slate text/surface roles from the design spec — every
            // screen reading colorScheme.onSurface/.onSurfaceVariant/.outline
            // (the large majority of the app) picks these up automatically.
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            onSurfaceVariant: AppColors.textSecondary,
            outline: AppColors.border,
            outlineVariant: AppColors.border,
            // ColorScheme.fromSeed derives its "surfaceContainer*" family
            // (chip backgrounds, the ResponsiveShell gutter on wide/landscape
            // layouts) from the seed hue — with a teal seed that comes out as
            // a faint yellow-green rather than a clean neutral. Pin them to
            // the same slate scale as everything else instead.
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF6F8FA),
            surfaceContainer: const Color(0xFFEEF1F4),
            surfaceContainerHigh: const Color(0xFFE7ECF1),
            surfaceContainerHighest: const Color(0xFFE2E8F0),
          );

    // Page background is a step darker than card surfaces (slate-50 vs.
    // white) so cards read as elevated content without needing shadows —
    // in dark mode the seeded surface seat already provides that contrast.
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
      // Clear typographic hierarchy: bold, tight titles for screen/section
      // headings; a slightly heavier titleMedium for card titles; body text
      // untouched from Material defaults (already tuned for readability).
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
      // The app bar keeps the brand navy in both modes.
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
