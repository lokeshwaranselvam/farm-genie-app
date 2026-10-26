import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/warning_popup.dart';
import '../services/farmgenie_api.dart';

class SalesDashboardScreen extends StatefulWidget {
  const SalesDashboardScreen({super.key});

  @override
  State<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends State<SalesDashboardScreen>
    with WarningPopupState {
  static final _url = Uri.parse('${FarmgenieApi.baseUrl}/sales-dashboard');
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
              warningMessage = 'Sales Dashboard could not be loaded.';
            });
          },
        ),
      );
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        warningMessage = null;
      });
    }
    try {
      await FarmgenieApi.prepareSalesDashboardSession();
      await _controller.loadRequest(_url);
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
        warningMessage = 'Sales Dashboard could not be loaded.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: _loadDashboard,
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
