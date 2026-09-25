import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/w_action_sheet.dart';

import '../support/l10n_harness.dart';

void main() {
  late String? result;

  Widget host() => wrapL10n(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showWActionSheet<String>(context, title: 'Options', actions: const [
              WSheetAction(label: 'Add set', value: 'add', icon: Icons.add),
              WSheetAction(label: 'Move up', value: 'up', icon: Icons.north, enabled: false),
              WSheetAction(label: 'Remove', value: 'rm', icon: Icons.delete_outline, destructive: true),
            ]);
          },
          child: const Text('open'),
        ),
      ));

  setUp(() => result = null);

  testWidgets('returns the tapped action value', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result, 'rm');
    expect(find.text('Options'), findsNothing);
  });

  testWidgets('a disabled action does nothing', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Options'), findsOneWidget);
  });

  testWidgets('rows are at least 56dp tall', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final row = find.ancestor(of: find.text('Add set'), matching: find.byKey(const ValueKey('sheet-action-0')));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
  });
}
