import 'dart:io';
import 'dart:ui' as ui;

import 'package:farmgenie/widgets/glass_home.dart';
import 'package:farmgenie/main.dart';
import 'package:farmgenie/screens/attendance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget fixture({
  String name = 'Akash',
  bool completed = true,
  bool checkedIn = false,
  bool loading = false,
  double textScale = 1,
  VoidCallback? onAction,
  VoidCallback? onRefresh,
  ValueChanged<int>? onNavigation,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: BotanicalBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 66,
          leadingWidth: 64,
          leading: const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 0, 10),
            child: FarmgenieGlassCard(
              radius: 30,
              child: Icon(Icons.menu_rounded),
            ),
          ),
          title: const FarmgenieHomeWordmark(),
          titleSpacing: 16,
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: FarmgenieGlassCard(
                radius: 30,
                padding: EdgeInsets.all(10),
                child: Text(
                  'A',
                  style: TextStyle(color: forestGreen, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            FarmgenieGreetingCard(name: name, checkedIn: checkedIn),
            const SizedBox(height: 10),
            FarmgenieAttendanceStatusCard(
              loading: loading,
              completed: completed,
              checkedIn: checkedIn,
              title: loading
                  ? 'Loading status...'
                  : completed
                  ? 'Work Completed'
                  : checkedIn
                  ? 'You are Checked In'
                  : 'Not Checked In',
              description: completed
                  ? 'Your check-in and check-out are complete for today.'
                  : checkedIn
                  ? 'Office: Head Office - Vanagaram'
                  : 'Check in to start your workday and begin today\'s work.',
              checkInTime: completed || checkedIn ? '4:34 PM' : '--:--',
              checkOutTime: completed ? '4:34 PM' : '--:--',
            ),
            const SizedBox(height: 9),
            FarmgenieAttendanceActionButton(
              label: completed
                  ? 'Work Completed'
                  : checkedIn
                  ? 'Check Out'
                  : 'Check In',
              completed: completed,
              checkout: checkedIn,
              busy: loading,
              onPressed: completed ? null : onAction,
            ),
            const SizedBox(height: 10),
            FarmgenieLocationCard(
              address: '3534+R54, Pallikuppam Perumal Koil St, Methpar Nagar, Maduravoyal, Vanagaram, Tamil Nadu 600116, India',
              loading: false,
              onRefresh: onRefresh,
            ),
          ],
        ),
        bottomNavigationBar: FarmgenieGlassBottomNavigation(
          selectedIndex: 0,
          onSelected: onNavigation ?? (_) {},
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final fonts = Directory('${artifacts.path}/material_fonts');
    final loader = FontLoader('Roboto')
      ..addFont(
        File('${fonts.path}/roboto-regular.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      )
      ..addFont(
        File('${fonts.path}/roboto-bold.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File('${fonts.path}/materialicons-regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
  });
  testWidgets('responsive glass home and large text do not overflow', (
    tester,
  ) async {
    for (final width in [320.0, 393.0, 600.0]) {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          fixture(name: 'Alexandria Employee', textScale: scale),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'width $width scale $scale',
        );
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
    'attendance action, completion, refresh and navigation preserve callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(393, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var actions = 0;
      var refreshes = 0;
      var selected = -1;
      await tester.pumpWidget(
        fixture(
          completed: false,
          onAction: () => actions++,
          onRefresh: () => refreshes++,
          onNavigation: (index) => selected = index,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Check In'));
      expect(actions, 1);
      await tester.tap(find.byTooltip('Refresh location'));
      expect(refreshes, 1);
      for (var i = 0; i < 4; i++) {
        await tester.tap(
          find.text(
            ['Home', 'Attendance', 'Leave Request', 'Material Request'][i],
          ),
        );
        expect(selected, i);
      }
      await tester.pumpWidget(
        fixture(completed: false, checkedIn: true, onAction: () => actions++),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Check Out'));
      expect(actions, 2);
      await tester.pumpWidget(fixture(onAction: () => actions++));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Work Completed'),
            )
            .onPressed,
        isNull,
      );
      expect(actions, 2);
    },
  );

  testWidgets('actual navigation keeps the existing home controller alive', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(393, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(onLogout: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final homeState = tester.state(
      find.byType(AttendanceScreen, skipOffstage: false).first,
    );
    await tester.tap(find.text('Attendance').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Home').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.state(find.byType(AttendanceScreen, skipOffstage: false).first),
      same(homeState),
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sales Dashboard'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Attendance'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Attendance Records'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('render reference home visual fixture', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(393, 730);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const key = ValueKey('preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: fixture(completed: false, onRefresh: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/ui-preview').create(recursive: true);
      await File('build/ui-preview/home-reference.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = true;
    expect(tester.takeException(), isNull);
  });
}
