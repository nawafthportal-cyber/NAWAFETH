import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Home Header — wraps PlatformTopBar with a branded background
// ─────────────────────────────────────────────────────────────────────────────

class HomeHeader extends StatelessWidget {
  final int notificationCount;
  final int chatCount;
  final VoidCallback? onMenuTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onChatsTap;

  const HomeHeader({
    super.key,
    this.notificationCount = 0,
    this.chatCount = 0,
    this.onMenuTap,
    this.onNotificationsTap,
    this.onChatsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(40)
                : AppColors.primary.withAlpha(12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              // Left side: menu button
              _HeaderIconButton(
                icon: Icons.menu_rounded,
                onTap: onMenuTap,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              // Center: logo / brand name
              const Expanded(child: _BrandLogo()),
              // Right side: notification + chat
              _NotificationButton(
                count: chatCount,
                icon: Icons.chat_bubble_outline_rounded,
                onTap: onChatsTap,
                isDark: isDark,
              ),
              const SizedBox(width: 4),
              _NotificationButton(
                count: notificationCount,
                icon: Icons.notifications_outlined,
                onTap: onNotificationsTap,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Brand icon
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: const Icon(
            Icons.window_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'نوافذ',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.primary,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;

  const _HeaderIconButton({
    required this.icon,
    this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          size: 20,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final int count;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;

  const _NotificationButton({
    required this.count,
    required this.icon,
    this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              icon,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          if (count > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isDark ? AppColors.bgDark : Colors.white,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
