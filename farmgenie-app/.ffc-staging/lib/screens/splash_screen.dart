import 'package:flutter/material.dart';

import '../services/farmgenie_api.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onReady});

  final ValueChanged<bool> onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    await precacheImage(
      const AssetImage('assets/images/farmgenie_logo.png'),
      context,
    );
    if (!mounted) return;
    await precacheImage(const AssetImage('logo-display.png'), context);
    bool signedIn = false;
    try {
      signedIn = await FarmgenieApi.hasSession();
    } catch (_) {}
    if (mounted) widget.onReady(signedIn);
  }

  @override
  Widget build(BuildContext context) {
    return const SplashArtwork();
  }
}

class SplashArtwork extends StatelessWidget {
  const SplashArtwork({super.key});
  @override
  Widget build(BuildContext context) {
    final logoSize = MediaQuery.sizeOf(context).shortestSide * .25;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Image(
            width: logoSize,
            height: logoSize,
            image: AssetImage('assets/images/farmgenie_logo.png'),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
