// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_plugin2/main.dart';

void main() {
  testWidgets('Lex home renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LexApp(home: SizedBox()));
    expect(find.text('LEX'), findsOneWidget);
    expect(find.text('Voice Mode'), findsOneWidget);
    expect(find.text('Vision Mode'), findsOneWidget);

    // Explicitly dispose the app tree to stop LiveKit internal timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  },
      skip:
          true); // LiveKit Room creates background timers in widget-test runtime.
}
