import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morixtrem/widgets/morixtrem_logo.dart';

void main() {
  testWidgets('wordmark shows morixtrem next to the mark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: MorixtremWordmark(logoSize: 48))),
      ),
    );

    expect(find.byType(MorixtremLogo), findsOneWidget);
    expect(find.textContaining('morixtrem'), findsOneWidget);
  });
}
