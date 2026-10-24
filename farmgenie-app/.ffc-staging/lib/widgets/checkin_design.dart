import 'package:flutter/material.dart';

const brandGreen = Color(0xFF00A65A);
const brandOrange = Color(0xFFFF4B20);

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.checkout = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy, checkout;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(
        colors: checkout
            ? [const Color(0xFFFF751D), const Color(0xFFF0200B)]
            : [const Color(0xFF22BC42), const Color(0xFF009F68)],
      ),
    ),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
      ),
    ),
  );
}

class WelcomeBanner extends StatelessWidget {
  const WelcomeBanner({super.key, required this.name, required this.checkedIn});
  final String name;
  final bool checkedIn;
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF03C87C), Color(0xFF009A76), Color(0xFF005632)],
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(23),
              child: FractionallySizedBox(
                widthFactor: .70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting,\n$name 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      checkedIn
                          ? 'Have a productive day!\nYou are checked in.'
                          : 'Manage your attendance, material requests and daily work with Farmgenie.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
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
}

class TimeTile extends StatelessWidget {
  const TimeTile({
    super.key,
    required this.label,
    required this.value,
    this.checkout = false,
  });
  final String label, value;
  final bool checkout;
  @override
  Widget build(BuildContext context) {
    final color = checkout ? brandOrange : brandGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(
              checkout ? Icons.logout_rounded : Icons.login_rounded,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF526078),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
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
