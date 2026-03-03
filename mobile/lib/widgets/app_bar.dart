import 'package:flutter/material.dart';
import '../constants/colors.dart';
import 'dart:async';

// ✅ استدعاء شاشة الإشعارات
import 'package:nawafeth/screens/notifications_screen.dart';
import 'package:nawafeth/screens/my_chats_screen.dart';
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/messaging_service.dart';
import 'package:nawafeth/services/notification_service.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String? title;
  final bool showSearchField;
  final bool showBackButton;
  final bool forceDrawerIcon; // جديد: لإجبار إظهار أيقونة القائمة بدلاً من الرجوع

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
    final mode = await AccountModeService.apiMode();
    final results = await Future.wait<int>([
      NotificationService.fetchUnreadCount(mode: mode),
      MessagingService.fetchUnreadCount(mode: mode),
    ]);
    if (!mounted) return;
    setState(() {
      _notificationUnread = results[0];
      _chatUnread = results[1];
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
    final bool shouldShowBack = !widget.forceDrawerIcon && (widget.showBackButton || canPop);

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
                  builder:
                      (context) => IconButton(
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
                        // ✅ فتح شاشة البحث الديناميكية
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(),
                          ),
                        );
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : const Color.fromRGBO(255, 255, 255, 0.15),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.2)
                                : const Color.fromRGBO(103, 58, 183, 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 20,
                              color: isDark ? Colors.white70 : AppColors.deepPurple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'بحث...',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : AppColors.deepPurple,
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

// ✅ شاشة البحث الديناميكية
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = "";

  // ✅ بيانات مزودي الخدمات (اسم، خدمات، صورة، توثيق)
  final List<Map<String, dynamic>> _providers = [
    {
      "name": "محمد القحطاني",
      "services": ["محامي", "استشارات قانونية"],
      "image": "assets/images/1.png",
      "verified": true,
    },
    {
      "name": "سارة العبدالله",
      "services": ["طبيبة أسنان"],
      "image": "assets/images/12.png",
      "verified": true,
    },
    {
      "name": "أحمد الغامدي",
      "services": ["مهندس مدني", "إشراف مشاريع"],
      "image": "assets/images/151.png",
      "verified": false,
    },
    {
      "name": "ريم العساف",
      "services": ["مصممة جرافيك", "هوية بصرية"],
      "image": "assets/images/251.jpg",
      "verified": true,
    },
    {
      "name": "خالد الحربي",
      "services": ["مبرمج تطبيقات", "مواقع ويب"],
      "image": "assets/images/551.png",
      "verified": false,
    },
    {
      "name": "منى الزهراني",
      "services": ["مدرسة لغة إنجليزية", "تحضير IELTS"],
      "image": "assets/images/879797.jpeg",
      "verified": true,
    },
    {
      "name": "شركة نافذة",
      "services": ["تسويق إلكتروني", "إدارة حسابات"],
      "image": "assets/images/gfo.png",
      "verified": true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final results =
        _providers.where((item) {
          final name = item["name"].toString();
          final services = (item["services"] as List).join(" ");
          return name.contains(_query) || services.contains(_query);
        }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("البحث", style: TextStyle(fontFamily: "Cairo")),
        backgroundColor: AppColors.deepPurple,
      ),
      body: Column(
        children: [
          // ✅ حقل البحث
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              onChanged: (value) {
                setState(() {
                  _query = value.trim();
                });
              },
              decoration: InputDecoration(
                hintText: "ابحث عن خدمة أو مقدم خدمة...",
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.deepPurple,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.deepPurple,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.deepPurple,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          // ✅ النتائج
          Expanded(
            child:
                results.isEmpty
                    ? const Center(
                      child: Text(
                        "لا توجد نتائج",
                        style: TextStyle(fontFamily: "Cairo", fontSize: 16),
                      ),
                    )
                    : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder:
                          (_, __) =>
                              Divider(color: Colors.grey.shade300, height: 1),
                      itemBuilder: (context, index) {
                        final provider = results[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8), // ✅ مربع
                            child: Image.asset(
                              provider["image"],
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                provider["name"],
                                style: const TextStyle(
                                  fontFamily: "Cairo",
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (provider["verified"])
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.verified,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            (provider["services"] as List).join(" • "),
                            style: const TextStyle(
                              fontFamily: "Cairo",
                              fontSize: 13,
                            ),
                          ),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "اخترت ${provider["name"]}: ${(provider["services"] as List).join(", ")}",
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
