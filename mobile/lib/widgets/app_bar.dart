import 'package:flutter/material.dart';
import '../constants/colors.dart';
import 'dart:async';

// ✅ استدعاء شاشة الإشعارات
import 'package:nawafeth/screens/notifications_screen.dart';
import 'package:nawafeth/screens/my_chats_screen.dart';
import 'package:nawafeth/screens/search_provider_screen.dart';
import 'package:nawafeth/services/unread_badge_service.dart';

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
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  int _notificationUnread = 0;
  int _chatUnread = 0;
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    _loadBadges();
    _badgeTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _loadBadges();
    });
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBadges() async {
    final badges = await UnreadBadgeService.fetch();
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  Widget _badgeIcon({
    required IconData icon,
    required Color color,
    required int count,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color),
        if (count > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : AppColors.primaryDark;

    // ✅ تحديد ما إذا كان يجب إظهار زر العودة تلقائياً
    // إذا كان forceDrawerIcon = true، لا تظهر زر الرجوع أبداً
    final bool canPop = Navigator.of(context).canPop();
    final bool shouldShowBack =
        !widget.forceDrawerIcon && (widget.showBackButton || canPop);

    return SafeArea(
      bottom: false,
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: 60,
        titleSpacing: 0,
        centerTitle: false,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // ✅ زر العودة أو القائمة الجانبية
              if (shouldShowBack)
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: iconColor,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              else
                Builder(
                  builder: (context) => IconButton(
                    icon: Icon(
                      Icons.menu,
                      color: iconColor,
                    ),
                    onPressed: () {
                      final scaffold = Scaffold.maybeOf(context);
                      if (scaffold?.hasDrawer ?? false) {
                        scaffold!.openDrawer();
                      } else {
                        debugPrint('❗ Scaffold لا يحتوي على drawer');
                      }
                    },
                  ),
                ),

              const SizedBox(width: 12),

              // ✅ عنوان أو حقل بحث
              if (widget.title != null)
                Expanded(
                  child: Text(
                    widget.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : AppColors.deepPurple,
                    ),
                  ),
                )
              else if (widget.showSearchField)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SearchProviderScreen(
                              showDrawer: false,
                              showBottomNavigation: false,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color.fromRGBO(255, 255, 255, 0.15),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : const Color.fromRGBO(103, 58, 183, 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 20,
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.deepPurple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'بحث...',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.deepPurple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),

              const Spacer(),

              // ✅ أيقونة الإشعارات
              IconButton(
                icon: _badgeIcon(
                  icon: Icons.notifications_none,
                  color: iconColor,
                  count: _notificationUnread,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  _loadBadges();
                },
              ),

              const SizedBox(width: 8),

              // ✅ المحادثات داخل التطبيق (بديل شعار التطبيق)
              IconButton(
                icon: _badgeIcon(
                  icon: Icons.chat_bubble_outline,
                  color: iconColor,
                  count: _chatUnread,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyChatsScreen(),
                    ),
                  );
                  _loadBadges();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
