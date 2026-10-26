import 'package:farmgenie/screens/login_screen.dart';
import 'package:farmgenie/services/remembered_login_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget loginApp(VoidCallback onLoggedIn) => MaterialApp(
  // Ahem's wide test glyphs overflow the existing Remember me row at 1.0.
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: const TextScaler.linear(.8)),
    child: child!,
  ),
  home: LoginScreen(onLoggedIn: onLoggedIn),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'opt out removes credentials and persists the unchecked preference',
    () async {
      final store = RememberedLoginStore();
      await store.save(
        remember: true,
        username: 'employee',
        password: ' secret ',
      );
      expect((await RememberedLoginStore().read()).password, ' secret ');
      await store.save(
        remember: false,
        username: 'employee',
        password: 'secret',
      );
      expect(await store.read(), (remember: false, username: '', password: ''));
      expect(
        (await const FlutterSecureStorage().readAll()).values.join(),
        isNot(contains('secret')),
      );
    },
  );

  testWidgets(
    'reopening login restores both fields and keeps password hidden',
    (tester) async {
      await RememberedLoginStore().save(
        remember: true,
        username: 'employee',
        password: ' secret ',
      );
      await tester.pumpWidget(loginApp(() {}));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, 'employee');
      expect(fields[1].controller!.text, ' secret ');
      expect(
        tester.widgetList<TextField>(find.byType(TextField)).last.obscureText,
        isTrue,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(fields[0].controller!.text, 'employee');
      expect((await RememberedLoginStore().read()).remember, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(loginApp(() {}));
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    },
  );

  for (final success in [true, false]) {
    testWidgets(
      'login ${success ? 'saves successful' : 'does not save rejected'} credentials',
      (tester) async {
        var loggedIn = false;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(loginApp(() => loggedIn = true));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextFormField).at(0),
              ' employee ',
            );
            await tester.enterText(
              find.byType(TextFormField).at(1),
              ' secret ',
            );
            await tester.ensureVisible(find.byType(FilledButton));
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            expect(request.bodyFields, {'usr': 'employee', 'pwd': ' secret '});
            return http.Response(
              '{}',
              success ? 200 : 401,
              headers: success
                  ? {'set-cookie': 'sid=test-session; Path=/'}
                  : {},
            );
          }),
        );
        expect(loggedIn, success);
        if (!success) {
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Warning'), findsOneWidget);
          final message =
              tester.widget<AlertDialog>(find.byType(AlertDialog)).content!
                  as Text;
          expect(find.text(message.data!), findsOneWidget);
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text(message.data!), findsNothing);
        }
        final saved = await RememberedLoginStore().read();
        expect(saved.username, success ? 'employee' : '');
        expect(saved.password, success ? ' secret ' : '');
      },
    );
  }
}
