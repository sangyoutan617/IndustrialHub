import 'package:flutter/material.dart';

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
