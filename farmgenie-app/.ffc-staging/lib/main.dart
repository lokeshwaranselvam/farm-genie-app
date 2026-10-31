import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/attendance_screen.dart';
import 'screens/erp_web_view_screen.dart';
import 'screens/face_enrollment_gate.dart';
import 'screens/login_screen.dart';
import 'screens/material_request_screen.dart';
import 'screens/mandatory_permissions_gate.dart';
import 'screens/leave_request_screen.dart';
import 'screens/sales_dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'services/farmgenie_api.dart';
import 'widgets/employee_avatar.dart';
import 'widgets/glass_home.dart';
import 'widgets/farmgenie_theme.dart';
import 'widgets/farmgenie_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await FarmgenieThemeController.initialize();
  runApp(const FarmgenieApp());
}

class FarmgenieApp extends StatefulWidget {
  const FarmgenieApp({super.key});

  @override
  State<FarmgenieApp> createState() => _FarmgenieAppState();
}

class _FarmgenieAppState extends State<FarmgenieApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Widget? _screen;
  bool _signedIn = false;
  bool _handlingExpiry = false;

  @override
  void initState() {
    super.initState();
    FarmgenieApi.sessionExpired.addListener(_onSessionExpired);
    _checkSession();
  }

  @override
  void dispose() {
    FarmgenieApi.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  Future<void> _checkSession() async {
    // null means ERP was unreachable: keep offline users on the home screen.
    final valid = await FarmgenieApi.validateSession();
    if (valid == false) {
      try {
        await FarmgenieApi.logout(remote: false);
      } catch (_) {
        // Local cleanup is best effort; the login screen is shown regardless.
      }
    }
    if (!mounted) return;
    if (valid == false) {
      _showLogin();
    } else {
      _showHome();
    }
  }

  Future<void> _onSessionExpired() async {
    if (!_signedIn || _handlingExpiry) return;
    _handlingExpiry = true;
    try {
      await FarmgenieApi.logout(remote: false);
    } catch (_) {
      // ERP already rejected the session; only local cleanup matters.
    } finally {
      _handlingExpiry = false;
    }
    _showLogin();
  }

  Widget _faceHome() {
    Future<void> signOut() async {
      try {
        await FarmgenieApi.logout();
      } finally {
        _showLogin();
      }
    }

    return MandatoryPermissionsGate(
      onSignOut: signOut,
      child: FaceEnrollmentGate(
        onSignOut: signOut,
        child: HomeScreen(onLogout: _showLogin),
      ),
    );
  }

  void _showHome() {
    if (!mounted) return;
    setState(() {
      _signedIn = true;
      _screen = _faceHome();
    });
  }

  void _showLogin() {
    if (!mounted) return;
    // Close pushed pages (e.g. Profile) and dialogs left over from the session.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _signedIn = false;
      _screen = LoginScreen(onLoggedIn: _showHome);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FarmgenieThemeChoice>(
      valueListenable: FarmgenieThemeController.choice,
      builder: (context, choice, child) => MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Farmgenie',
        theme: farmgenieTheme(choice),
        builder: (context, child) =>
            BotanicalBackground(child: child ?? const SizedBox.shrink()),
        home: _screen ?? const Scaffold(backgroundColor: Colors.white),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final Set<int> _visitedPages = {0};
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _materialRequestKey = GlobalKey<ErpWebViewScreenState>();
  final _salesDashboardKey = GlobalKey<ErpWebViewScreenState>();

  /// System back: close the drawer, step back in WebView history, or return
  /// to Home. Only the Home tab lets back leave the app.
  Future<void> _handleSystemBack() async {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    final index = _index;
    final webView = switch (index) {
      2 => _materialRequestKey.currentState,
      4 => _salesDashboardKey.currentState,
      _ => null,
    };
    if (webView != null && await webView.goBack()) return;
    if (mounted && _index == index) _selectPage(0);
  }

  void _selectPage(int index) {
    setState(() {
      _visitedPages.add(index);
      _index = index;
    });
  }

  void _selectBottomPage(int index) {
    _selectPage(
      index == 2
          ? 3
          : index == 3
          ? 2
          : index,
    );
  }

  int get _bottomIndex {
    if (_index == 3) return 2;
    if (_index == 2) return 3;
    return _index < 2 ? _index : 0;
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Your Farmgenie ERP session will be closed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FarmgenieApi.logout();
    } catch (_) {
      // Local session is cleared by the API service even if ERP is offline.
    }
    if (mounted) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final isWebView = _index == 2 || _index == 4;
    final pages = [
      AttendanceScreen(onOpenPage: _selectPage),
      _visitedPages.contains(1)
          ? const AttendanceScreen(recordsOnly: true)
          : const SizedBox.shrink(),
      _visitedPages.contains(2)
          ? MaterialRequestScreen(key: _materialRequestKey)
          : const SizedBox.shrink(),
      _visitedPages.contains(3)
          ? const LeaveRequestScreen()
          : const SizedBox.shrink(),
      _visitedPages.contains(4)
          ? SalesDashboardScreen(key: _salesDashboardKey)
          : const SizedBox.shrink(),
    ];
    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        toolbarHeight: 66,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.white,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        leadingWidth: 64,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
            child: FarmgenieGlassCard(
              radius: 30,
              child: IconButton(
                tooltip: 'Open navigation menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: Icon(
                  Icons.menu_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 16,
        title: const FarmgenieHomeWordmark(),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 20, 10),
            child: FarmgenieGlassCard(
              radius: 30,
              child: IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                ),
                tooltip: 'Profile',
                icon: ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: FarmgenieApi.employeeProfile,
                  builder: (context, profile, child) => EmployeeAvatar(
                    radius: 15,
                    name: profile['employee_name']?.toString() ?? 'Employee',
                    image: profile['image']?.toString(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawerEnableOpenDragGesture: !isWebView,
      drawer: Drawer(
        child: SafeArea(
          child: ListTileTheme(
            textColor: homeInk,
            iconColor: Theme.of(context).colorScheme.primary,
            selectedColor: Theme.of(context).colorScheme.primary,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const FarmgenieHomeWordmark(scale: 1.1),
                    ),
                  ),
                ),
                for (final (index, icon, label) in const [
                  (0, Icons.home_filled, 'Home'),
                  (1, Icons.calendar_month_outlined, 'Attendance'),
                  (2, Icons.inventory_2_outlined, 'Material Request'),
                  (3, Icons.event_available_outlined, 'Leave Request'),
                  (4, Icons.analytics_outlined, 'Sales Dashboard'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ListTile(
                      leading: Icon(icon),
                      title: Text(label),
                      selected: _index == index,
                      onTap: () {
                        _selectPage(index);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: homeSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1, color: cardBorder),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('Log out'),
                    onTap: _logout,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: FarmgenieGlassBottomNavigation(
        selectedIndex: _bottomIndex,
        onSelected: _selectBottomPage,
      ),
    );
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleSystemBack();
      },
      child: BotanicalBackground(child: scaffold),
    );
  }
}
