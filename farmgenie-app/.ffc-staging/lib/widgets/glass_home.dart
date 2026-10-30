import 'package:flutter/material.dart';

const forestGreen = Color(0xFF17633A);
const sidebarGreen = Color(0xFF0F4A2C);
const sidebarSelected = Color(0xFF1F7A48);
const homeSecondary = Color(0xFF5B6B62);
const homeInk = Color(0xFF17251C);
const pageBackground = Color(0xFFF4F7F3);
const cardBorder = Color(0xFFE2EAE3);
const iconTint = Color(0xFFE6F2E8);

Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 220);

/// White dashboard card. [blur] and [opacity] are kept for existing callers
/// from the earlier glass style and no longer change the surface.
class FarmgenieGlassCard extends StatelessWidget {
  const FarmgenieGlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 14,
    this.blur = 0,
    this.opacity = .54,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, blur, opacity;

  // A Material surface, so ListTiles and ink splashes inside stay visible.
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0F3D24),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: cardBorder),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Rounded square behind a dashboard icon, as on the stat cards.
class FarmgenieIconTile extends StatelessWidget {
  const FarmgenieIconTile({
    super.key,
    required this.icon,
    this.color = forestGreen,
    this.background = iconTint,
    this.size = 44,
  });
  final IconData icon;
  final Color color, background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(size * .27),
    ),
    child: Icon(icon, color: color, size: size * .56),
  );
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
  Widget build(BuildContext context) =>
      enabled ? ColoredBox(color: pageBackground, child: child) : child;
}

/// Reuses the original mark; the crop only lays out the existing brand horizontally.
class FarmgenieHomeWordmark extends StatelessWidget {
  const FarmgenieHomeWordmark({super.key, this.light = false});

  /// White text for the dark-green navigation drawer.
  final bool light;

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
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Farmgenie',
                  maxLines: 1,
                  style: TextStyle(
                    color: light ? Colors.white : forestGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -.5,
                  ),
                ),
                Text(
                  'From Earth to Heart',
                  maxLines: 1,
                  style: TextStyle(
                    color: light
                        ? const Color(0xFFB7E4C7)
                        : const Color(0xFF64923C),
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Page header: greeting, employee name and today's attendance line.
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
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            greeting,
            style: const TextStyle(
              color: forestGreen,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              color: homeInk,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            checkedIn
                ? 'You are checked in. Have a productive day!'
                : 'Your attendance and daily work at a glance.',
            style: const TextStyle(
              color: homeSecondary,
              fontSize: 14,
              height: 1.35,
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
    final done = checkedIn || completed;
    final color = done ? const Color(0xFF1E8A4C) : const Color(0xFFB86A00);
    return FarmgenieGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FarmgenieIconTile(
                icon: done
                    ? Icons.check_circle_outline_rounded
                    : Icons.schedule_rounded,
                color: color,
                background: done ? iconTint : const Color(0xFFFFF3DF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attendance Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: homeSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: _motion(context),
                      child: Align(
                        key: ValueKey(title),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 19,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: done ? forestGreen : const Color(0xFF8A4B00),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: homeSecondary,
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
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FarmgenieAttendanceTimeCard(
                  label: 'Check In',
                  value: checkInTime,
                ),
              ),
              const SizedBox(width: 10),
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
    );
  }
}

/// Stat tile: icon square, label and a large value.
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAF7),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cardBorder),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 120;
          return Row(
            children: [
              FarmgenieIconTile(
                icon: checkout ? Icons.logout_rounded : Icons.login_rounded,
                size: compact ? 32 : 40,
                color: checkout ? const Color(0xFFC2412D) : forestGreen,
                background: checkout ? const Color(0xFFFDECEA) : iconTint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: homeSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: homeInk,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
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
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: _motion(context),
      color: completed
          ? const Color(0xFF6E9A7E)
          : checkout
          ? const Color(0xFFC2412D)
          : forestGreen,
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: TextButton(
          onPressed: busy ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
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
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

/// One tile of the Quick Actions card.
class FarmgenieQuickAction {
  const FarmgenieQuickAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.tag,
    required this.tagColor,
    required this.buttonLabel,
    required this.onPressed,
  });
  final IconData icon;
  final String title, description, tag, buttonLabel;
  final Color tagColor;
  final VoidCallback onPressed;
}

/// Shortcut tiles with a tag and an action button, two per row on phones.
class FarmgenieQuickActionsCard extends StatelessWidget {
  const FarmgenieQuickActionsCard({super.key, required this.actions});
  final List<FarmgenieQuickAction> actions;

  @override
  Widget build(BuildContext context) => FarmgenieGlassCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            FarmgenieIconTile(icon: Icons.auto_awesome_rounded, size: 36),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  color: homeInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 300 ? 2 : 1;
            return Column(
              children: [
                for (var i = 0; i < actions.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = i; j < i + columns; j++) ...[
                          if (j > i) const SizedBox(width: 10),
                          Expanded(
                            child: j < actions.length
                                ? _QuickActionTile(action: actions[j])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});
  final FarmgenieQuickAction action;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAF7),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cardBorder),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(action.icon, color: action.tagColor, size: 26),
          const SizedBox(height: 8),
          Text(
            action.title,
            style: const TextStyle(
              color: homeInk,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            action.description,
            style: const TextStyle(
              color: homeSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 10),
          // Full width, so the tag sits left and the button right.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: action.tagColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      action.tag,
                      style: TextStyle(
                        color: action.tagColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: action.onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: forestGreen,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(action.buttonLabel),
                ),
              ],
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
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        const FarmgenieIconTile(icon: Icons.location_on_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Location',
                style: TextStyle(
                  color: homeInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 12,
                  color: homeSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Refresh location',
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: iconTint,
            foregroundColor: forestGreen,
            minimumSize: const Size(40, 40),
          ),
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 24),
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
      radius: 18,
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
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelected(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: _motion(context),
                          width: 64,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: i == selectedIndex
                                ? iconTint
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
                                : const Color(0xFF66736C),
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
                                    : const Color(0xFF66736C),
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
