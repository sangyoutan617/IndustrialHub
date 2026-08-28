import 'package:flutter/material.dart';

/// Caps how wide the app's content is allowed to get.
///
/// In portrait, the app is centred at [maxContentWidth] once the viewport
/// grows past it (a tablet held upright, a desktop window, the web build) —
/// otherwise a login form's fields stretch into full-width bars and
/// dashboard cards blow up to absurd sizes. In landscape, phones need the
/// opposite treatment: a phone rotated sideways should fill the screen, not
/// get squeezed into a portrait-width column with big empty gutters on
/// either side. [maxContentWidthLandscape] is set high enough that no real
/// or emulated Android phone's landscape width ever hits it, while a
/// genuinely wide viewport (tablet landscape, desktop, web) still gets the
/// same centred-gutter treatment as portrait.
///
/// Wired once at [MaterialApp.builder] so every screen and every dialog in
/// every module inherits the same behaviour without having to opt in — the
/// app lays out against the capped width, so there is no per-screen change
/// and nothing in the individual modules needs editing.
class ResponsiveShell extends StatelessWidget {
  final Widget child;

  /// The widest the content is ever laid out at in portrait. 640 keeps forms
  /// readable and the 3-up dashboard grid comfortable, while being wide
  /// enough that ordinary phones in portrait never hit the cap at all.
  final double maxContentWidth;

  /// The widest the content is ever laid out at in landscape. Deliberately
  /// much larger than [maxContentWidth] — this only guards against genuinely
  /// wide viewports (tablets, desktop, web), never ordinary phone landscape.
  final double maxContentWidthLandscape;

  const ResponsiveShell({
    super.key,
    required this.child,
    this.maxContentWidth = 640,
    this.maxContentWidthLandscape = 1100,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final cap = isLandscape ? maxContentWidthLandscape : maxContentWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrower than the cap: nothing to do, let the app fill the screen.
        if (constraints.maxWidth <= cap) return child;
        // Wider than the cap: centre the app and fill the sides with a
        // neutral gutter so the narrower layout reads as deliberate rather
        // than as a rendering glitch. Theme-aware so it stays subtle in dark
        // mode instead of glaring light grey.
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cap),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
