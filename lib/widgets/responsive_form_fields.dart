import 'package:flutter/material.dart';

/// Marks a full-width break point inside a [ResponsiveFormFields] child list:
/// a [SectionHeader], [Divider], or the Save [FilledButton]. Kept so existing
/// call sites don't need to change, but the wrapped child renders exactly as
/// if [FormBreak] weren't there — see [ResponsiveFormFields].
class FormBreak extends StatelessWidget {
  final Widget child;

  const FormBreak(this.child, {super.key});

  @override
  Widget build(BuildContext context) => child;
}

/// A single [Column] of form fields, one per row, full width, in every
/// orientation.
///
/// Landscape used to pair consecutive fields side by side into two-up
/// [Row]s — but that's the left/right-split pattern the app's landscape
/// design avoids. Fields simply get more horizontal room from the wider
/// landscape content area (see [ResponsiveShell]) instead of being packed
/// two per row. [FormBreak] children (section headers, dividers, the save
/// button) already rendered full-width either way, so this class is now a
/// thin, orientation-independent wrapper — kept so the 9 form screens that
/// build their field list with it don't need to change.
///
/// Because every form screen's [TextEditingController]s are `late final`
/// fields on the screen's own [State] (disposed in `dispose()`, never owned
/// by the [TextFormField] element), typed text already survives rotation
/// regardless of how this widget lays fields out.
class ResponsiveFormFields extends StatelessWidget {
  final List<Widget> children;

  const ResponsiveFormFields({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
