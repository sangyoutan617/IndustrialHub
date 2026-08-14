import 'package:flutter/material.dart';

/// Caps how wide the app's content is allowed to get.
///
/// On phones in portrait — and on most phones in landscape — the app fills
/// the screen exactly as before. On a genuinely wide viewport (a tablet in
/// landscape, a desktop window, or the web build) the whole app is centred
/// at [maxContentWidth] instead of stretching edge to edge. Edge-to-edge
/// stretch is what otherwise distorts the login form's fields into
/// full-width bars and blows the dashboard cards up to absurd sizes on a
/// large screen.
///
/// Wired once at [MaterialApp.builder] so every screen and every dialog in
/// every module inherits the same behaviour without having to opt in — the
/// app lays out against the capped width, so there is no per-screen change
/// and nothing in the individual modules needs editing.
class ResponsiveShell extends StatelessWidget {
  final Widget child;

  /// The widest the content is ever laid out at. 640 keeps forms readable
  /// and the 3-up dashboard grid comfortable, while being wide enough that
  /// ordinary phones (portrait and landscape) never hit the cap at all.
  final double maxContentWidth;

  const ResponsiveShell({
    super.key,
    required this.child,
    this.maxContentWidth = 640,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrower than the cap: nothing to do, let the app fill the screen.
        if (constraints.maxWidth <= maxContentWidth) return child;
        // Wider than the cap: centre the app and fill the sides with a
        // neutral gutter so the narrower layout reads as deliberate rather
        // than as a rendering glitch.
        return ColoredBox(
          color: const Color(0xFFEDEFEE),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
