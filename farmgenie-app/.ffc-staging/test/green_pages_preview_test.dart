import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:farmgenie/screens/leave_request_screen.dart';
import 'package:farmgenie/screens/login_screen.dart';
import 'package:farmgenie/screens/profile_screen.dart';
import 'package:farmgenie/widgets/farmgenie_theme.dart';
import 'package:farmgenie/widgets/glass_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final fonts = Directory('${artifacts.path}/material_fonts');
    for (final font in ['Roboto', 'MaterialIcons']) {
      final loader = FontLoader(font);
      for (final name
          in font == 'Roboto'
              ? ['roboto-regular.ttf', 'roboto-bold.ttf']
              : ['materialicons-regular.otf']) {
        loader.addFont(
          File('${fonts.path}/$name')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    }
  });

  testWidgets('green pages render on mobile and preserve leave form controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'farmgenie_sid': 'preview-session',
      'farmgenie_user': 'employee@example.test',
    });
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((request) async {
      final message = request.url.path.endsWith('mobile_checkin')
          ? <String, dynamic>{
              'status': 'success',
              'employee': {'name': 'EMP-001', 'employee_name': 'Akash'},
              'today_logs': [],
              'latest_checkin_id': '',
              'next_action': 'IN',
            }
          : <String, dynamic>{
              'name': 'EMP-001',
              'employee_name': 'Akash',
              'company': 'Farmgenie',
              'department': 'Operations',
              'designation': 'Sales Executive',
              'branch': 'Chennai',
              'leave_approver': 'manager@example.test',
            };
      return http.Response(jsonEncode({'message': message}), 200);
    });
    await http.runWithClient(() async {
      for (final width in [320.0, 393.0, 600.0]) {
        tester.view.physicalSize = Size(width, 850);
        for (final page in ['login', 'leave', 'profile']) {
          final child = switch (page) {
            'login' => LoginScreen(onLoggedIn: () {}),
            'leave' => Scaffold(
              appBar: AppBar(title: const Text('Leave Request')),
              body: const LeaveRequestScreen(),
            ),
            _ => const ProfileScreen(),
          };
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('preview'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: farmgenieTheme().copyWith(
                  textTheme: farmgenieTheme().textTheme.apply(
                    fontFamily: 'Roboto',
                  ),
                ),
                builder: (context, child) => BotanicalBackground(child: child!),
                home: child,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (page == 'login') {
            await tester.runAsync(
              () => precacheImage(
                const AssetImage('assets/images/farmgenie_logo.png'),
                tester.element(find.byType(Scaffold).first),
              ),
            );
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull, reason: '$page at $width');
          if (page == 'leave') {
            expect(find.text('Employee ID: EMP-001'), findsOneWidget);
            await tester.tap(find.byType(Checkbox));
            await tester.pumpAndSettle();
            expect(
              tester.widget<Checkbox>(find.byType(Checkbox)).value,
              isTrue,
            );
          }
          if (width == 393) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('preview')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/ui-preview').create(recursive: true);
              await File('build/ui-preview/green-$page.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }, () => client);
  });
}
