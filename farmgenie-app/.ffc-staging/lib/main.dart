import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/attendance_screen.dart';
import 'screens/face_enrollment_gate.dart';
import 'screens/login_screen.dart';
import 'screens/material_request_screen.dart';
import 'screens/leave_request_screen.dart';
import 'screens/sales_dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'services/farmgenie_api.dart';
import 'widgets/employee_avatar.dart';
import 'widgets/glass_home.dart';
import 'widgets/farmgenie_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const FarmgenieApp());
}

class FarmgenieApp extends StatefulWidget {
  const FarmgenieApp({super.key});

  @override
  State<FarmgenieApp> createState() => _FarmgenieAppState();
}

class _FarmgenieAppState extends State<FarmgenieApp> {
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final signedIn = await FarmgenieApi.hasSession();
    if (!mounted) return;
    setState(() {
      _screen = signedIn ? _faceHome() : LoginScreen(onLoggedIn: _showHome);
    });
  }

  Widget _faceHome() => FaceEnrollmentGate(
    onSignOut: () async {
      try {
        await FarmgenieApi.logout();
      } finally {
        _showLogin();
      }
    },
    child: HomeScreen(onLogout: _showLogin),
  );

  void _showHome() {
    if (mounted) setState(() => _screen = _faceHome());
  }

  void _showLogin() {
    if (mounted) setState(() => _screen = LoginScreen(onLoggedIn: _showHome));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Farmgenie',
      theme: farmgenieTheme(),
      builder: (context, child) =>
          BotanicalBackground(child: child ?? const SizedBox.shrink()),
      home:
          _screen ??
          const Scaffold(
            body: Center(
              child: SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  strokeWidth: 7,
                  color: Color(0xFF2D6A3F),
                ),
              ),
            ),
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
      const AttendanceScreen(),
      _visitedPages.contains(1)
          ? const AttendanceScreen(recordsOnly: true)
          : const SizedBox.shrink(),
      _visitedPages.contains(2)
          ? const MaterialRequestScreen()
          : const SizedBox.shrink(),
      _visitedPages.contains(3)
          ? const LeaveRequestScreen()
          : const SizedBox.shrink(),
      _visitedPages.contains(4)
          ? const SalesDashboardScreen()
          : const SizedBox.shrink(),
    ];
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _index == 0
          ? AppBar(
              backgroundColor: Colors.transparent,
              toolbarHeight: 66,
              systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
              leadingWidth: 64,
              leading: Builder(
                builder: (context) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
                  child: FarmgenieGlassCard(
                    radius: 30,
                    opacity: .65,
                    child: IconButton(
                      tooltip: 'Open navigation menu',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(
                        Icons.menu_rounded,
                        color: Color(0xFF203831),
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
                    opacity: .65,
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
                          name:
                              profile['employee_name']?.toString() ??
                              'Employee',
                          image: profile['image']?.toString(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : AppBar(
              leading: isWebView
                  ? IconButton(
                      tooltip: 'Back',
                      onPressed: () => _selectPage(0),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : null,
              title: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  'logo-display.png',
                  height: 34,
                  width: 118,
                  fit: BoxFit.contain,
                ),
              ),
              centerTitle: false,
              titleSpacing: isWebView ? 0 : -30,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
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
                        radius: 17,
                        name:
                            profile['employee_name']?.toString() ?? 'Employee',
                        image: profile['image']?.toString(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      drawerEnableOpenDragGesture: !isWebView,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Image.asset(
                    'logo-display.png',
                    width: 170,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                selected: _index == 0,
                onTap: () {
                  _selectPage(0);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Attendance'),
                selected: _index == 1,
                onTap: () {
                  _selectPage(1);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Material Request'),
                selected: _index == 2,
                onTap: () {
                  _selectPage(2);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Leave Request'),
                selected: _index == 3,
                onTap: () {
                  _selectPage(3);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Sales Dashboard'),
                selected: _index == 4,
                onTap: () {
                  _selectPage(4);
                  Navigator.pop(context);
                },
              ),
              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Log out'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _index == 0
          ? FarmgenieGlassBottomNavigation(
              selectedIndex: _bottomIndex,
              onSelected: _selectBottomPage,
            )
          : NavigationBar(
              selectedIndex: _bottomIndex,
              onDestinationSelected: _selectBottomPage,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.access_time_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Attendance',
                ),
                NavigationDestination(
                  icon: Icon(Icons.event_available_outlined),
                  selectedIcon: Icon(Icons.event_available),
                  label: 'Leave Request',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Material Request',
                ),
              ],
            ),
    );
    return PopScope(
      canPop: !isWebView,
      child: BotanicalBackground(child: scaffold),
    );
  }
}
