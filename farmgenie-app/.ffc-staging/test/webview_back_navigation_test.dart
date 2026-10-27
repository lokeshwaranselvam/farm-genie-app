import 'package:farmgenie/main.dart';
import 'package:farmgenie/services/farmgenie_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Platform fakes exercise navigation without a native WebView.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _WebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebView(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();

  static bool canGoBackResult = false;
  static int goBackCalls = 0;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<bool> canGoBack() async => canGoBackResult;

  @override
  Future<void> goBack() async {
    goBackCalls++;
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();

  static NavigationRequestCallback? navigationRequest;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    navigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _WebView extends PlatformWebViewWidget {
  _WebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const Text('WebView content');
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await dismissWarnings(tester);
}

Future<void> openFromDrawer(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Open navigation menu').first);
  await settle(tester);
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(title)),
  );
  await settle(tester);
}

Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

void main() {
  testWidgets(
    'system back walks WebView history, then returns Home; only Home exits',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      FarmgenieApi.resetSessionCache();
      _Controller.canGoBackResult = false;
      _Controller.goBackCalls = 0;
      final previousPlatform = WebViewPlatform.instance;
      WebViewPlatform.instance = _WebViewPlatform();
      if (previousPlatform != null) {
        addTearDown(() => WebViewPlatform.instance = previousPlatform);
      }
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Previous route')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(onLogout: () {})),
      );
      await settle(tester);

      for (final title in ['Material Request', 'Sales Dashboard']) {
        await openFromDrawer(tester, title);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.byType(DrawerButton), findsNothing);

        // With WebView history, back steps within the WebView.
        _Controller.canGoBackResult = true;
        final calls = _Controller.goBackCalls;
        await systemBack(tester);
        expect(_Controller.goBackCalls, calls + 1);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text('Previous route'), findsNothing);

        // Without history, back returns to Home instead of leaving the app.
        _Controller.canGoBackResult = false;
        await systemBack(tester);
        expect(_Controller.goBackCalls, calls + 1);
        expect(find.byTooltip('Open navigation menu'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
        expect(find.text('Previous route'), findsNothing);

        // The app bar back button also returns Home.
        await openFromDrawer(tester, title);
        await tester.tap(find.byTooltip('Back'));
        await settle(tester);
        expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      }

      // Non-WebView tabs also return Home rather than exiting.
      await openFromDrawer(tester, 'Leave Request');
      // Non-home tabs use the standard app bar with its own drawer button.
      expect(find.byType(DrawerButton), findsOneWidget);
      await systemBack(tester);
      expect(find.byType(DrawerButton), findsNothing);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      expect(find.text('Previous route'), findsNothing);

      // On Home, back keeps its default behavior and leaves this route.
      await systemBack(tester);
      expect(find.text('Previous route'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    },
  );

  testWidgets('WebViews only navigate within the ERP origin', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    FarmgenieApi.resetSessionCache();
    _Delegate.navigationRequest = null;
    final previousPlatform = WebViewPlatform.instance;
    WebViewPlatform.instance = _WebViewPlatform();
    if (previousPlatform != null) {
      addTearDown(() => WebViewPlatform.instance = previousPlatform);
    }
    await tester.pumpWidget(MaterialApp(home: HomeScreen(onLogout: () {})));
    await settle(tester);
    await openFromDrawer(tester, 'Material Request');
    final decide = _Delegate.navigationRequest!;
    Future<NavigationDecision> request(String url) async =>
        decide(NavigationRequest(url: url, isMainFrame: true));

    final site = FarmgenieApi.baseUrl;
    expect(await request('$site/indent-cy'), NavigationDecision.navigate);
    expect(await request('about:blank'), NavigationDecision.navigate);
    expect(
      await request('https://evil.example.test/phish'),
      NavigationDecision.prevent,
    );
    for (final url in ['intent://scan#Intent;end', 'mailto:hr@example.test']) {
      expect(await request(url), NavigationDecision.prevent);
    }

    final expiredBefore = FarmgenieApi.sessionExpired.value;
    expect(
      await request('$site/login?redirect-to=%2Findent-cy'),
      NavigationDecision.prevent,
    );
    expect(FarmgenieApi.sessionExpired.value, expiredBefore + 1);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });
}

Future<void> dismissWarnings(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final ok = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('OK'),
    );
    if (ok.evaluate().isEmpty) return;
    await tester.tap(ok);
  }
}
