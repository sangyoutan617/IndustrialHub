import 'package:flutter/material.dart';

/// Switches between a portrait and a landscape layout based on the current
/// device orientation, without duplicating expensive or stateful children.
///
/// ## Build-once convention (important for correctness)
///
/// If a child is stateful or triggers a side-effect when constructed —
/// an [AiInsightCard] that calls Gemini, a [FutureBuilder]-backed section
/// that issues a network request — build it **once** as a local variable
/// before calling [ResponsiveTwoPane], then pass the same instance to both
/// builders:
///
/// ```dart
/// Widget _buildReady() {
///   // Built once; the same object reference is passed to both layouts.
///   final aiInsight = AiInsightCard(buildPrompt: ..., system: ...);
///
///   return ResponsiveTwoPane(
///     portrait: (context) => Column(children: [summary, aiInsight, ...]),
///     landscape: (context) => Row(children: [
///       Expanded(child: Column(children: [summary, aiInsight])),
///       Expanded(child: Column(children: [actions])),
///     ]),
///   );
/// }
/// ```
///
/// Constructing a widget fresh inside a builder closure is safe only when
/// the widget is purely presentational (a [Card], a [Text]) — anything that
/// issues a network call on construction must follow the pattern above, or
/// it will re-fetch on every orientation change, regressing caching and
/// quota usage.
///
/// See [CapacityDashboardScreen._buildReady] for the existing reference
/// implementation that introduced this pattern.
class ResponsiveTwoPane extends StatelessWidget {
  /// Called when the device is in portrait orientation (or when no specific
  /// orientation is detected). Receives a [BuildContext] for theme look-ups.
  final WidgetBuilder portrait;

  /// Called when the device is in landscape orientation.
  final WidgetBuilder landscape;

  const ResponsiveTwoPane({
    super.key,
    required this.portrait,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) => orientation == Orientation.landscape
          ? landscape(context)
          : portrait(context),
    );
  }
}
