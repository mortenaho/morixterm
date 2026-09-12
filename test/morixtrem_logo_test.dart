import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morixterm/widgets/morixtrem_logo.dart';

void main() {
  testWidgets('wordmark shows morixterm next to the mark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: MorixtermWordmark(logoSize: 48))),
      ),
    );

    expect(find.byType(MorixtermLogo), findsOneWidget);
    expect(find.textContaining('morixterm'), findsOneWidget);
  });
}
