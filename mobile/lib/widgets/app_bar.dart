import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ✅ استدعاء شاشة الإشعارات
import 'package:nawafeth/screens/notifications_screen.dart';
import 'package:nawafeth/screens/my_chats_screen.dart';
import 'package:nawafeth/services/unread_badge_service.dart';

import 'platform_top_bar.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String? title;
  final bool showSearchField;
  final bool showBackButton;
  final bool
      forceDrawerIcon; // جديد: لإجبار إظهار أيقونة القائمة بدلاً من الرجوع

  const CustomAppBar({
    super.key,
    this.title,
    this.showSearchField = true,
    this.showBackButton = false,
    this.forceDrawerIcon = false, // افتراضياً false
  });

  @override
  Size get preferredSize => const Size.fromHeight(86);

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  int _notificationUnread = 0;
  int _chatUnread = 0;
  ValueListenable<UnreadBadges>? _badgeListenable;

  @override
  void initState() {
    super.initState();
    _badgeListenable = UnreadBadgeService.acquire();
    _badgeListenable!.addListener(_handleBadgeChange);
    _handleBadgeChange();
    UnreadBadgeService.refresh(force: true);
  }

  @override
  void dispose() {
    _badgeListenable?.removeListener(_handleBadgeChange);
    UnreadBadgeService.release();
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeListenable?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  Future<void> _loadBadges() async {
    await UnreadBadgeService.refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    final bool shouldShowBack =
        !widget.forceDrawerIcon && (widget.showBackButton || canPop);

    return PlatformTopBar(
      pageLabel: widget.title,
      showBackButton: shouldShowBack,
      showMenuButton: !shouldShowBack,
      onMenuTap: () {
        final scaffold = Scaffold.maybeOf(context);
        if (scaffold?.hasDrawer ?? false) {
          scaffold!.openDrawer();
        } else {
          debugPrint('❗ Scaffold لا يحتوي على drawer');
        }
      },
      onNotificationsTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const NotificationsScreen(),
          ),
        );
        _loadBadges();
      },
      onChatsTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MyChatsScreen(),
          ),
        );
        _loadBadges();
      },
      notificationCount: _notificationUnread,
      chatCount: _chatUnread,
    );
  }
}
