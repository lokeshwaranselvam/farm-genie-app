import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmgenie_fresh_cart/screens/request_screen.dart';
import 'package:farmgenie_fresh_cart/services/workday_controller.dart';
import 'package:farmgenie_fresh_cart/theme/brand_theme.dart';
import 'widget_test.dart' show tapVisible;

void main() {
  testWidgets('leave dates save a local request without changing attendance', (tester) async {
    final workday = WorkdayController(today: DateTime(2026, 10, 20));
    await tester.pumpWidget(MaterialApp(theme: Brand.theme, home: Scaffold(
      body: RequestScreen(workday: workday, leave: true))));
    await tester.enterText(find.byType(TextFormField), 'Family appointment');
    await tapVisible(tester, find.byKey(const ValueKey('leave-dates')));
    await tapVisible(tester, find.byTooltip('Switch to input'));
    final fields = find.descendant(of: find.byType(DateRangePickerDialog),
      matching: find.byType(TextFormField));
    await tester.enterText(fields.at(0), '10/21/2026');
    await tester.enterText(fields.at(1), '10/22/2026');
    await tapVisible(tester, find.text('OK'));
    await tapVisible(tester, find.text('Save demo request'));
    expect(workday.leaves.single.title, 'Casual leave');
    expect(workday.leaves.single.detail, contains('Family appointment'));
    expect(workday.record(DateTime(2026, 10, 21)).checkIn, isNull);
    await tester.pumpWidget(const SizedBox());
    workday.dispose();
  });
}

