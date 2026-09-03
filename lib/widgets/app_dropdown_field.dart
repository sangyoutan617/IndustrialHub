import 'package:flutter/material.dart';

class AppDropdownField<T> extends StatelessWidget {
  final String idPrefix;
  final String label;
  final String? helperText;
  final int helperMaxLines;
  final T? value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final bool required;
  final String requiredMessage;

  const AppDropdownField({
    super.key,
    required this.idPrefix,
    required this.label,
    this.helperText,
    this.helperMaxLines = 2,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.enabled = true,
    this.required = true,
    this.requiredMessage = 'Required',
  });

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      key: ValueKey('$idPrefix-$value'),
      initialValue: value,
      validator: required ? (v) => v == null ? requiredMessage : null : null,
      builder: (field) => DropdownMenu<T>(
        enabled: enabled,
        initialSelection: value,
        expandedInsets: EdgeInsets.zero,
        label: Text(label),
        helperText: helperText,
        errorText: field.errorText,
        inputDecorationTheme: InputDecorationTheme(
          helperMaxLines: helperMaxLines,
          errorMaxLines: helperMaxLines,
        ),
        dropdownMenuEntries: entries,
        onSelected: (v) {
          field.didChange(v);
          onChanged(v);
        },
      ),
    );
  }
}
