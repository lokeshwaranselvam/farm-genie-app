import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/warning_popup.dart';
import '../services/farmgenie_api.dart';

class MaterialRequestScreen extends StatefulWidget {
  const MaterialRequestScreen({super.key});

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends State<MaterialRequestScreen>
    with WarningPopupState {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
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
              warningMessage = 'Material request page could not be loaded.';
            });
          },
        ),
      );
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      warningMessage = null;
    });
    try {
      await FarmgenieApi.prepareWebSession();
      if (!mounted) return;
      await _controller.loadRequest(
        Uri.parse('${FarmgenieApi.baseUrl}/indent-cy'),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          warningMessage = error is FarmgenieApiException
              ? error.message
              : 'Could not open Material Request. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF2D6A3F)),
          ),
        if (warningMessage != null)
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
