import 'package:flutter/material.dart';

/// Shows a single-line text-input dialog and returns the trimmed value, or
/// null if cancelled (or unchanged/empty). The [TextEditingController] lives
/// inside this dialog's own [State] and is disposed in its `dispose()`, so it
/// outlives the field until the route is fully gone — avoiding the framework
/// assertion that a controller disposed in a caller's `finally` (which races
/// the route's exit animation) can trigger.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialValue;
  final String confirmLabel;

  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
