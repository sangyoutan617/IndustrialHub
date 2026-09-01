import 'package:flutter/material.dart';

class FormBreak extends StatelessWidget {
  final Widget child;

  const FormBreak(this.child, {super.key});

  @override
  Widget build(BuildContext context) => child;
}

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
