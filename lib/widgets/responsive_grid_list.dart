import 'package:flutter/material.dart';

/// A single-column list of items.
///
/// Landscape used to switch this to a multi-column [GridView] to "use the
/// extra width" — but a grid of short cards is exactly the kind of density
/// the app's landscape design avoids: it reads as more information at once
/// rather than the same information with more breathing room. So this stays
/// a single [ListView.builder] in every orientation; the extra landscape
/// width instead reaches each card through the wider content area above it
/// (see [ResponsiveShell]), letting a card's own content lay out more
/// comfortably rather than being packed two-per-row.
class ResponsiveGridList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;

  const ResponsiveGridList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
