import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmgenie_fresh_cart/app.dart';

// Generate review images with: flutter test tool/preview_test.dart --update-goldens
void main() {
  testWidgets('render employee app previews', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const FarmgenieApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await expectLater(find.byType(FarmgenieApp),
      matchesGoldenFile('../docs/previews/login.png'));
    await tester.enterText(find.byType(TextFormField).first, 'aarav');
    await tester.enterText(find.byType(TextFormField).last, 'demo');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(FarmgenieApp),
      matchesGoldenFile('../docs/previews/home.png'));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(FarmgenieApp),
      matchesGoldenFile('../docs/previews/profile.png'));
    await tester.ensureVisible(find.text('Logout'));
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(FarmgenieApp),
      matchesGoldenFile('../docs/previews/logout.png'));
    await tester.pumpWidget(const SizedBox());
  });
}

