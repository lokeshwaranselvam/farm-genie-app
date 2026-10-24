import 'package:farmgenie/main.dart';
import 'package:flutter/material.dart';
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

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();

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

void main() {
  testWidgets(
    'only app back leaves active WebViews; other pages keep back behavior',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      for (final title in ['Material Request', 'Sales Dashboard']) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(of: find.byType(Drawer), matching: find.text(title)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.byType(DrawerButton), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text('Previous route'), findsNothing);

        await tester.tap(find.byTooltip('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byTooltip('Open navigation menu'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
      }

      // Offstage WebViews must not block the home route's normal back behavior.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Previous route'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    },
  );
}
