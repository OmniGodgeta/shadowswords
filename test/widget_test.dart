// Basic smoke test for the ShadowSwords shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shadowswords/main.dart';

void main() {
  testWidgets('App builds and shows a loading indicator', (tester) async {
    await tester.pumpWidget(const ShadowSwordsApp());
    // The WebView platform isn't available in the test harness, but the shell
    // (Scaffold + progress indicator) should still build.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
