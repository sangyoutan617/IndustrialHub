import 'package:flutter/material.dart';

/// Marks a full-width break point inside a [ResponsiveFormFields] child list:
/// a [SectionHeader], [Divider], or the Save [FilledButton]. In landscape mode,
/// [ResponsiveFormFields] pairs consecutive non-break children side by side
/// and resets its pairing state at each [FormBreak], so headers and the save
/// button always span the full width rather than being paired with a field.
///
/// ```dart
/// ResponsiveFormFields(children: [
///   TextFormField(...),              // paired in landscape →
///   TextFormField(...),              // ← with this one
///   FormBreak(SectionHeader(...)),   // full-width; resets pairing
///   TextFormField(...),              // rendered full-width (odd trailing)
///   FormBreak(FilledButton(...)),    // full-width save button
/// ])
/// ```
class FormBreak extends StatelessWidget {
  final Widget child;

  const FormBreak(this.child, {super.key});

  @override
  Widget build(BuildContext context) => child;
}

/// A list of form fields that adapts to orientation:
///
/// - **Portrait** → single [Column]; each child at full width, exactly as
///   it would appear in a normal `ListView`-based form.
/// - **Landscape** → consecutive non-[FormBreak] children are paired into
///   side-by-side [Row]s (`Row` of two [Expanded]). The current pending pair
///   is flushed at each [FormBreak], so section headers, dividers, and the
///   save button always stay full-width. An odd trailing field (unpaired)
///   is rendered full-width rather than being stretched into a lone half-row.
///
/// ## Why typed text survives rotation
///
/// Every form screen's [TextEditingController]s are `late final` fields on
/// the screen's own [State], disposed in `dispose()` — they are never owned
/// by the [TextFormField] element itself. When the orientation changes and
/// [OrientationBuilder] rebuilds into a differently-shaped tree (single
/// [Column] ↔ [Column] of [Row] pairs), the [TextFormField] elements are
/// unmounted and remounted at new tree positions, but each remounted field
/// reads its initial value from `controller.value` — the same controller
/// object, untouched by the remount. **Typed text survives.**
///
/// One accepted trade-off: the field that has keyboard focus at the moment of
/// rotation may lose focus and dismiss the keyboard (a minor UX blip, not
/// data loss), because [FocusNode] identity is tied to element identity, and
/// none of the current form screens pass explicit [FocusNode]s. Verify
/// on-device in Phase E's form batch: type into a field, rotate mid-type,
/// confirm text is present.
///
/// ## Usage
///
/// Wrap the existing list of fields (from `ListView`'s `children:`) with
/// [ResponsiveFormFields], using [FormBreak] to mark the elements that must
/// always span the full width:
///
/// ```dart
/// Form(
///   key: _formKey,
///   child: ListView(
///     padding: const EdgeInsets.all(16),
///     children: [
///       ResponsiveFormFields(children: [
///         TextFormField(controller: _nameController, ...),
///         FormBreak(const SectionHeader(title: 'Details')),
///         TextFormField(controller: _rateController, ...),
///         TextFormField(controller: _hoursController, ...),
///         TextFormField(controller: _uptimeController, ...),
///         DropdownButtonFormField(...),
///         FormBreak(FilledButton(onPressed: _save, child: const Text('Save'))),
///       ]),
///     ],
///   ),
/// )
/// ```
class ResponsiveFormFields extends StatelessWidget {
  final List<Widget> children;

  const ResponsiveFormFields({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return _buildPortrait();
        }
        return _buildLandscape();
      },
    );
  }

  Widget _buildPortrait() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildLandscape() {
    final rows = <Widget>[];
    Widget? pending; // a non-break child waiting to be paired

    void flushPending() {
      if (pending != null) {
        // Odd trailing field — render full-width rather than a lone half-row.
        rows.add(pending!);
        pending = null;
      }
    }

    for (final child in children) {
      if (child is FormBreak) {
        flushPending();
        rows.add(child); // full-width break element
      } else if (pending == null) {
        pending = child; // hold and wait for a partner
      } else {
        // Pair the held child with this one.
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: pending!),
              const SizedBox(width: 16),
              Expanded(child: child),
            ],
          ),
        );
        pending = null;
      }
    }
    flushPending(); // any remaining unpaired field

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
