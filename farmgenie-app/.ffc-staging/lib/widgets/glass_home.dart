import 'dart:ui';

import 'package:flutter/material.dart';

const forestGreen = Color(0xFF005B46);
const homeSecondary = Color(0xFF496171);

Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 220);

class FarmgenieGlassCard extends StatelessWidget {
  const FarmgenieGlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 21,
    this.blur = 0,
    this.opacity = .54,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, blur, opacity;

  @override
  Widget build(BuildContext context) {
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .48, 1],
          colors: [
            Colors.white.withValues(alpha: (opacity + .22).clamp(0, 1)),
            Colors.white.withValues(alpha: (opacity - .10).clamp(0, 1)),
            const Color(0xFFE0F8F0).withValues(alpha: opacity),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: .98),
          width: 1.8,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: Colors.white.withValues(alpha: .3), spreadRadius: 1),
          BoxShadow(
            color: forestGreen.withValues(alpha: .10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: blur > 0
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: surface,
              )
            : surface,
      ),
    );
  }
}

class FarmgenieHomeEntrance extends StatelessWidget {
  const FarmgenieHomeEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: _motion(context),
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 6),
        child: child,
      ),
    ),
  );
}

class BotanicalBackground extends StatelessWidget {
  const BotanicalBackground({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (enabled) ...[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF4FFFC), Color(0xFFD9FAE9), Color(0xFFE9FFF6)],
              stops: [0, .55, 1],
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.8, -.8),
                radius: 1.2,
                colors: [Color(0x504CECA0), Color(0x00FFFFFF)],
              ),
            ),
          ),
        ),
      ],
      child,
    ],
  );
}

/// Reuses the original mark; the crop only lays out the existing brand horizontally.
class FarmgenieHomeWordmark extends StatelessWidget {
  const FarmgenieHomeWordmark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Farmgenie. From Earth to Heart',
    image: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: SizedBox(
              width: 34,
              height: 34,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minWidth: 67,
                maxWidth: 67,
                minHeight: 54,
                maxHeight: 54,
                child: Image.asset(
                  'logo-display.png',
                  width: 67,
                  height: 54,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Farmgenie',
                  maxLines: 1,
                  style: TextStyle(
                    color: forestGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -.5,
                  ),
                ),
                Text(
                  'From Earth to Heart',
                  maxLines: 1,
                  style: TextStyle(color: Color(0xFF64923C), fontSize: 8.5),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class FarmgenieGreetingCard extends StatelessWidget {
  const FarmgenieGreetingCard({
    super.key,
    required this.name,
    required this.checkedIn,
  });
  final String name;
  final bool checkedIn;
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'GOOD MORNING,'
        : hour < 17
        ? 'GOOD AFTERNOON,'
        : 'GOOD EVENING,';
    return FarmgenieGlassCard(
      opacity: .3,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x40F4FFF9),
                    Color(0x6562E895),
                    Color(0x5575DEBC),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 19, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    color: Color(0xFF57747A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$name \u{1F44B}',
                  style: const TextStyle(
                    color: forestGreen,
                    fontSize: 34,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: .70,
                  child: Text(
                    checkedIn ? 'Have a productive day!\nYou are checked in.' : 'Manage your attendance, material requests and daily work with Farmgenie.',
                    style: const TextStyle(
                      color: homeSecondary,
                      fontSize: 13.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FarmgenieAttendanceStatusCard extends StatelessWidget {
  const FarmgenieAttendanceStatusCard({
    super.key,
    required this.loading,
    required this.completed,
    required this.checkedIn,
    required this.title,
    required this.description,
    required this.checkInTime,
    required this.checkOutTime,
  });
  final bool loading, completed, checkedIn;
  final String title, description, checkInTime, checkOutTime;
  @override
  Widget build(BuildContext context) {
    final color = checkedIn || completed
        ? const Color(0xFF16B86A)
        : const Color(0xFFFFA447);
    return FarmgenieGlassCard(
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: .07),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: .13),
                        ),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [color, color.withValues(alpha: .72)],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .65),
                            ),
                          ),
                          child: Icon(
                            checkedIn || completed
                                ? Icons.check_circle_outline_rounded
                                : Icons.schedule_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        const Text(
                          'Attendance Status',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF394E60),
                          ),
                        ),
                        const SizedBox(height: 7),
                        AnimatedSwitcher(
                          duration: _motion(context),
                          child: Align(
                            key: ValueKey(title),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w900,
                                color: checkedIn || completed
                                    ? forestGreen
                                    : const Color(0xFF98501D),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          description,
                          style: const TextStyle(
                            color: homeSecondary,
                            fontWeight: FontWeight.w400,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: FarmgenieAttendanceTimeCard(
                      label: 'Check In',
                      value: checkInTime,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: FarmgenieAttendanceTimeCard(
                      label: 'Check Out',
                      value: checkOutTime,
                      checkout: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FarmgenieAttendanceTimeCard extends StatelessWidget {
  const FarmgenieAttendanceTimeCard({
    super.key,
    required this.label,
    required this.value,
    this.checkout = false,
  });
  final String label, value;
  final bool checkout;
  @override
  Widget build(BuildContext context) => FarmgenieGlassCard(
    radius: 18,
    blur: 0,
    opacity: .45,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 120;
        return Row(
          children: [
            Container(
              width: compact ? 30 : 42,
              height: compact ? 40 : 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color:
                    (checkout
                            ? const Color(0xFFFFDDD6)
                            : const Color(0xFFB3F1D3))
                        .withValues(alpha: .65),
                border: Border.all(color: Colors.white.withValues(alpha: .7)),
              ),
              child: Icon(
                checkout ? Icons.logout_rounded : Icons.login_rounded,
                size: compact ? 22 : 26,
                color: checkout ? const Color(0xFFFF563A) : forestGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF304858),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class FarmgenieAttendanceActionButton extends StatelessWidget {
  const FarmgenieAttendanceActionButton({
    super.key,
    required this.label,
    required this.completed,
    required this.checkout,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final bool completed, checkout, busy;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(21),
    child: AnimatedContainer(
      duration: _motion(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: checkout && !completed
              ? const [Color(0xFFFFAE70), Color(0xFFFF563A), Color(0xFFD83C27)]
              : const [Color(0xFF77F39A), Color(0xFF08B882), Color(0xFF008B72)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: .98),
          width: 1.8,
        ),
      ),
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: TextButton(
              onPressed: busy ? null : onPressed,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(21),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          completed
                              ? Icons.check_circle
                              : checkout
                              ? Icons.logout_rounded
                              : Icons.login_rounded,
                          size: 25,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

class FarmgenieLocationCard extends StatelessWidget {
  const FarmgenieLocationCard({
    super.key,
    required this.address,
    required this.loading,
    required this.onRefresh,
  });
  final String address;
  final bool loading;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => FarmgenieGlassCard(
    radius: 21,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFCDF9E5), Color(0xFFBFF4DE)],
            ),
          ),
          child: const Icon(
            Icons.location_on_outlined,
            size: 29,
            color: forestGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: homeSecondary,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Refresh location',
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: .8),
            foregroundColor: forestGreen,
            minimumSize: const Size(40, 40),
          ),
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 25),
        ),
      ],
    ),
  );
}

class FarmgenieGlassBottomNavigation extends StatelessWidget {
  const FarmgenieGlassBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(15, 10, 15, 10),
    child: FarmgenieGlassCard(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Semantics(
                selected: i == selectedIndex,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSelected(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: _motion(context),
                          width: 69,
                          height: 33,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: i == selectedIndex
                                ? const Color(0xFFBFF5D5).withValues(alpha: .85)
                                : Colors.transparent,
                          ),
                          child: Icon(
                            [
                              Icons.home_filled,
                              Icons.access_time_rounded,
                              Icons.event_available_outlined,
                              Icons.inventory_2_outlined,
                            ][i],
                            size: 24,
                            color: i == selectedIndex
                                ? forestGreen
                                : const Color(0xFF515D5B),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              [
                                'Home',
                                'Attendance',
                                'Leave Request',
                                'Material Request',
                              ][i],
                              style: TextStyle(
                                fontSize: 10.5,
                                color: i == selectedIndex
                                    ? forestGreen
                                    : const Color(0xFF52616D),
                                fontWeight: i == selectedIndex
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
