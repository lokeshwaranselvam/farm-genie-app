import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/warning_popup.dart';
import '../services/farmgenie_api.dart';

/// Signed-in ERP page shown inside the app; navigation is locked to the ERP.
class ErpWebViewScreen extends StatefulWidget {
  const ErpWebViewScreen({
    super.key,
    required this.path,
    required this.loadFailedMessage,
    required this.openFailedMessage,
  });

  /// ERP path such as `/indent-cy`, resolved against [FarmgenieApi.baseUrl].
  final String path;

  /// Shown when the page itself fails to load.
  final String loadFailedMessage;

  /// Shown when the session cannot be prepared for an unexpected reason.
  final String openFailedMessage;

  @override
  State<ErpWebViewScreen> createState() => ErpWebViewScreenState();
}

class ErpWebViewScreenState extends State<ErpWebViewScreen>
    with WarningPopupState {
  late final WebViewController _controller;
  bool _loading = true;

  static String get _origin => Uri.parse(FarmgenieApi.baseUrl).origin;

  static bool _isErpUrl(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.origin == _origin;

  static bool _isLoginPage(Uri uri) =>
      _isErpUrl(uri) &&
      uri.path.replaceFirst(RegExp(r'/+$'), '') == '/login';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri == null || !_isErpUrl(uri)) {
              return NavigationDecision.prevent;
            }
            if (_isLoginPage(uri)) {
              // ERP sends signed-out users to /login; return to app login.
              FarmgenieApi.notifySessionExpired();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            // Server redirects may bypass onNavigationRequest on some
            // platforms, so also catch the login page when it starts.
            final uri = Uri.tryParse(url);
            if (uri != null && _isLoginPage(uri)) {
              FarmgenieApi.notifySessionExpired();
            }
            if (!mounted) return;
            setState(() {
              _loading = true;
              warningMessage = null;
            });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;
            setState(() {
              _loading = false;
              warningMessage = widget.loadFailedMessage;
            });
          },
        ),
      );
    _loadPage();
  }

  /// Steps back in the WebView history; false when there is nothing to undo.
  Future<bool> goBack() async {
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return true;
      }
    } catch (_) {
      // Treat platform failures as "no history" so back still leaves the page.
    }
    return false;
  }

  Future<void> _loadPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        warningMessage = null;
      });
    }
    try {
      await FarmgenieApi.prepareWebSession();
      if (!mounted) return;
      await _controller.loadRequest(
        Uri.parse('${FarmgenieApi.baseUrl}${widget.path}'),
      );
    } on FarmgenieApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        warningMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        warningMessage = widget.openFailedMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = warningMessage;
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                color: Color(0xFF2D6A3F),
              ),
            ),
          ),
        if (message != null)
          Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 38),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadPage,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
