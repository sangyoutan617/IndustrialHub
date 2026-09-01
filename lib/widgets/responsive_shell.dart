import 'package:flutter/material.dart';

class ResponsiveShell extends StatelessWidget {
  final Widget child;

  final double maxContentWidth;

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
        if (constraints.maxWidth <= cap) return child;
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
