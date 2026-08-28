import 'package:flutter/material.dart';

/// A list that adapts its layout to the device orientation:
/// - **Portrait** → [ListView.builder] (single-column, full-width cards).
/// - **Landscape** → [GridView.builder] with a fixed cross-axis count.
///
/// Both orientations use the same [itemBuilder] callback, so each screen's
/// existing card-building logic is untouched — only the surrounding
/// scroll container changes.
///
/// ## Tuning card density
///
/// The default [landscapeChildAspectRatio] (3.2) suits a typical
/// [ListTile]-height card at 2 columns. If cards on a particular screen are
/// taller (e.g. multi-line subtitles, a status chip row) or you need 3
/// columns, adjust the ratio per-screen:
///
/// ```dart
/// ResponsiveGridList(
///   itemCount: _items.length,
///   itemBuilder: (context, index) => _buildCard(_items[index]),
///   landscapeChildAspectRatio: 2.5,   // taller card
///   landscapeCrossAxisCount: 3,        // three columns
/// )
/// ```
///
/// A lower ratio → taller cells; a higher ratio → shorter cells.
class ResponsiveGridList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;

  /// Number of columns in landscape mode. Defaults to 2.
  final int landscapeCrossAxisCount;

  /// Aspect ratio (width ÷ height) of each grid cell in landscape mode.
  /// Tune this per-screen if the default produces squeezed or too-tall cards.
  /// Defaults to 3.2.
  final double landscapeChildAspectRatio;

  const ResponsiveGridList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.landscapeCrossAxisCount = 2,
    this.landscapeChildAspectRatio = 3.2,
  });

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          return GridView.builder(
            padding: padding,
            itemCount: itemCount,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: landscapeCrossAxisCount,
              mainAxisSpacing: 0,
              crossAxisSpacing: 8,
              childAspectRatio: landscapeChildAspectRatio,
            ),
            itemBuilder: itemBuilder,
          );
        }
        return ListView.builder(
          padding: padding,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
