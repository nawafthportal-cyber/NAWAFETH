import 'package:flutter/material.dart';
import '../widgets/app_bar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../models/chat_thread_model.dart';
import '../services/messaging_service.dart';
import '../services/auth_service.dart';
import '../services/account_mode_service.dart';
import 'chat_detail_screen.dart';

class MyChatsScreen extends StatefulWidget {
  const MyChatsScreen({super.key});

  @override
  State<MyChatsScreen> createState() => _MyChatsScreenState();
}

class _MyChatsScreenState extends State<MyChatsScreen> {
  String selectedFilter = "الكل";
  String searchQuery = "";

  bool _isProviderAccount = false;
  bool _isLoading = true;
  String? _errorMessage;

  List<ChatThread> _threads = [];
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isProvider = await AccountModeService.isProviderMode();
    _myUserId = await AuthService.getUserId();

    if (mounted) {
      setState(() {
        _isProviderAccount = isProvider;
        if (!_isProviderAccount && selectedFilter == 'عملاء') {
          selectedFilter = 'الكل';
        }
      });
    }

    await _fetchThreads();
  }

  Future<void> _fetchThreads() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final threads = await MessagingService.fetchThreads(
        mode: _isProviderAccount ? 'provider' : 'client',
      );
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل المحادثات';
      });
    }
  }

  // ✅ فلترة المحادثات
  List<ChatThread> getFilteredChats() {
    List<ChatThread> filtered = [..._threads];

    // استبعاد المحظورة والمؤرشفة
    filtered = filtered.where((t) => !t.isBlocked && !t.isArchived).toList();

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where((t) => t.peerDisplayName.contains(searchQuery) || t.peerPhone.contains(searchQuery))
          .toList();
    }

    if (selectedFilter == "غير مقروءة") {
      filtered = filtered.where((t) => t.unreadCount > 0).toList();
    } else if (selectedFilter == "مفضلة") {
      filtered = filtered.where((t) => t.isFavorite).toList();
    } else if (selectedFilter == "عملاء") {
      if (_isProviderAccount) {
        filtered = filtered.where((t) => t.clientLabel?.isNotEmpty == true).toList();
      }
    } else if (selectedFilter == "الأحدث") {
      filtered.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return filtered;
    }

    // ✅ الغير مقروءة دائمًا بالأعلى (باستثناء فلتر الأحدث)
    filtered.sort((a, b) {
      if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
      if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });

    return filtered;
  }

  // ✅ خيارات المحادثة
  void _showChatOptions(ChatThread thread) {
    final isUnread = thread.unreadCount > 0;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: Icon(
              isUnread ? Icons.mark_email_read : Icons.mark_chat_unread,
              color: Colors.deepPurple,
            ),
            title: Text(isUnread ? "اجعلها مقروءة" : "اجعلها غير مقروءة"),
            onTap: () async {
              Navigator.pop(context);
              if (isUnread) {
                await MessagingService.markRead(thread.threadId);
              } else {
                await MessagingService.markUnread(thread.threadId);
              }
              _fetchThreads();
            },
          ),
          ListTile(
            leading: const Icon(Icons.star, color: Colors.deepPurple),
            title: Text(
              thread.isFavorite ? "إزالة من المفضلة" : "إضافة للمفضلة",
            ),
            onTap: () async {
              Navigator.pop(context);
              await MessagingService.toggleFavorite(
                thread.threadId,
                remove: thread.isFavorite,
              );
              _fetchThreads();
            },
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text(thread.isBlocked ? "إلغاء الحظر" : "حظر"),
            onTap: () async {
              Navigator.pop(context);
              await MessagingService.toggleBlock(
                thread.threadId,
                remove: thread.isBlocked,
              );
              _fetchThreads();
            },
          ),
          ListTile(
            leading: const Icon(Icons.report, color: Colors.orange),
            title: const Text("إبلاغ"),
            onTap: () {
              Navigator.pop(context);
              _showReportDialog(thread);
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined, color: Colors.black54),
            title: const Text("أرشفة"),
            onTap: () async {
              Navigator.pop(context);
              await MessagingService.toggleArchive(thread.threadId);
              _fetchThreads();
            },
          ),
        ],
      ),
    );
  }

  // ✅ نموذج الإبلاغ عن المحادثة
  void _showReportDialog(ChatThread thread) {
    final TextEditingController reasonController = TextEditingController();
    String selectedReason = "محتوى غير لائق";
    bool isSending = false;

    final reasons = [
      "محتوى غير لائق",
      "احتيال أو نصب",
      "إزعاج أو مضايقة",
      "انتحال شخصية",
      "محتوى مخالف للشروط",
      "أخرى",
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.report, color: Colors.orange, size: 28),
                ),
                const SizedBox(width: 12),
                const Text(
                  "إبلاغ عن محادثة",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // معلومات الطرف الآخر
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.deepPurple),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            thread.peerDisplayName,
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "سبب الإبلاغ:",
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedReason,
                        isExpanded: true,
                        items: reasons
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(r, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedReason = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "تفاصيل إضافية (اختياري):",
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: "اكتب التفاصيل هنا...",
                      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: isSending
                    ? null
                    : () async {
                        setDialogState(() => isSending = true);
                        final result = await MessagingService.report(
                          thread.threadId,
                          reason: selectedReason,
                          details: reasonController.text.trim().isNotEmpty
                              ? reasonController.text.trim()
                              : null,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.success
                                  ? "تم إرسال البلاغ للإدارة. شكراً لك"
                                  : result.error ?? "فشل إرسال البلاغ",
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: result.success ? Colors.green : Colors.red,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSending
                    ? const SizedBox(
                        height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("إرسال البلاغ", style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// تنسيق وقت آخر رسالة
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} د';
    if (diff.inDays < 1) {
      final h = dt.hour > 12 ? dt.hour - 12 : dt.hour;
      final amPm = dt.hour >= 12 ? 'م' : 'ص';
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m $amPm';
    }
    if (diff.inDays == 1) return 'الأمس';
    if (diff.inDays < 7) {
      const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sortedChats = getFilteredChats();

    // ✅ مجموع جميع الرسائل غير المقروءة
    final int totalUnread = _threads.fold<int>(0, (sum, t) => sum + t.unreadCount);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const CustomDrawer(),
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(60),
        child: CustomAppBar(title: 'محادثاتي'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ✅ حقل البحث
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "بحث عن محادثة...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) => setState(() => searchQuery = val),
              ),
            ),

            // ✅ الفلاتر
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip("الكل"),
                    const SizedBox(width: 8),
                    _buildFilterChip("غير مقروءة", unreadCount: totalUnread),
                    const SizedBox(width: 8),
                    _buildFilterChip("مفضلة"),
                    if (_isProviderAccount) ...[
                      const SizedBox(width: 8),
                      _buildFilterChip("عملاء"),
                    ],
                    const SizedBox(width: 8),
                    _buildFilterChip("الأحدث"),
                  ],
                ),
              ),
            ),

            // ✅ محتوى المحادثات
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchThreads,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                                child: const Text("إعادة المحاولة",
                                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : sortedChats.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "لا توجد محادثات",
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchThreads,
                              color: Colors.deepPurple,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: sortedChats.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final thread = sortedChats[index];
                                  return _buildChatTile(thread);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: -1),
    );
  }

  Widget _buildChatTile(ChatThread thread) {
    final bool isUnread = thread.unreadCount > 0;
    final bool isFavorite = thread.isFavorite;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              threadId: thread.threadId,
              peerName: thread.peerDisplayName,
              peerPhone: thread.peerPhone,
              peerCity: thread.peerCity,
              peerId: thread.peerId,
              peerProviderId: thread.peerProviderId,
            ),
          ),
        );
        // تحديث عند العودة
        _fetchThreads();
      },
      onLongPress: () => _showChatOptions(thread),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUnread
              ? Colors.deepPurple.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnread
                ? Colors.deepPurple.withValues(alpha: 0.4)
                : Colors.grey.shade200,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // ✅ صورة + حالة الاتصال
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.deepPurple.shade100,
                  child: Text(
                    thread.peerDisplayName.isNotEmpty
                      ? thread.peerDisplayName[0]
                      : '?',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // ✅ التفاصيل
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.peerDisplayName,
                          style: TextStyle(
                            fontFamily: "Cairo",
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (isFavorite) const Icon(Icons.star, size: 18, color: Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    thread.lastMessage.isNotEmpty ? thread.lastMessage : "لا توجد رسائل بعد",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 13,
                      color: isUnread ? Colors.black87 : Colors.black54,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ✅ الوقت + عدد غير المقروءة
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(thread.lastMessageAt),
                  style: const TextStyle(fontSize: 12, color: Colors.black45, fontFamily: "Cairo"),
                ),
                if (isUnread)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${thread.unreadCount}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: "Cairo",
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            // ✅ زر الخيارات
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _showChatOptions(thread),
              child: const Icon(Icons.more_vert, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ ويدجت الفلاتر مع دعم عدّاد للغير مقروءة
  Widget _buildFilterChip(String label, {int? unreadCount}) {
    final isSelected = selectedFilter == label;
    final bool showUnreadBadge = label == "غير مقروءة" && (unreadCount ?? 0) > 0;

    return GestureDetector(
      onTap: () => setState(() => selectedFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.deepPurple),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 13,
                color: isSelected ? Colors.white : Colors.deepPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (showUnreadBadge) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.deepPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unreadCount.toString(),
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.deepPurple : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
