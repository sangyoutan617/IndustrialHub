import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/widgets/text_prompt_dialog.dart';

/// Minimal host: a button that opens the prompt dialog and stores whatever
/// it resolves to, so the test can assert on the returned value without
/// needing a real screen.
class _Harness extends StatefulWidget {
  const _Harness({this.validator});

  final String? Function(String value)? validator;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? result;
  bool opened = false;

  @override
  Widget build(BuildContext context) {
    // The Builder gives the button a BuildContext that's a *descendant* of
    // MaterialApp (this State's own `context`, captured by `build`, is an
    // ancestor of the MaterialApp it returns — showDialog needs a
    // descendant to find MaterialLocalizations).
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final value = await showTextPromptDialog(
                context,
                title: 'Rename',
                label: 'Name',
                validator: widget.validator,
              );
              setState(() {
                result = value;
                opened = true;
              });
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'default validator rejects an empty value and keeps the dialog open',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Confirm with the field left empty.
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
      // The dialog is still up — Cancel is still on screen.
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets('typing a value and confirming pops the trimmed text', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '  Widget A  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(state.opened, isTrue);
    expect(state.result, 'Widget A');
    // The dialog is gone — Cancel is no longer on screen.
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a custom validator is used instead of the default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Harness(validator: (v) => v == 'nope' ? 'Not that one' : null),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'nope');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Not that one'), findsOneWidget);
    expect(find.text('Required'), findsNothing);
  });
}
