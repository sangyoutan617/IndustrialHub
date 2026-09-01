import 'package:flutter/material.dart';

Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
  String confirmLabel = 'Save',
  String? Function(String value)? validator,
  IconData? icon,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
      validator: validator,
      icon: icon,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialValue;
  final String confirmLabel;
  final String? Function(String value)? validator;
  final IconData? icon;

  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
    required this.validator,
    required this.icon,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: widget.icon != null ? Icon(widget.icon) : null,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: widget.label),
          validator: (v) {
            final value = v ?? '';
            final custom = widget.validator;
            if (custom != null) return custom(value);
            return value.trim().isEmpty ? 'Required' : null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
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
