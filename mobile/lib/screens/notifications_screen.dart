// ignore_for_file: unused_field
import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/account_mode_service.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  String _activeMode = 'client';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _totalCount = 0;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initModeAndLoad();
  }

  Future<void> _initModeAndLoad() async {
    final mode = await AccountModeService.apiMode();
    if (!mounted) return;
    setState(() => _activeMode = mode);
    _loadNotifications();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final page = await NotificationService.fetchNotifications(mode: _activeMode);
      if (!mounted) return;
      setState(() {
        _notifications = page.notifications;
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل الإشعارات';
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    try {
      final page = await NotificationService.fetchNotifications(
        mode: _activeMode,
        offset: _notifications.length,
      );
      if (!mounted) return;
      setState(() {
        _notifications.addAll(page.notifications);
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  // ─── تمييز الكل كمقروء ───
  Future<void> _markAllRead() async {
    final success = await NotificationService.markAllRead(mode: _activeMode);
    if (!mounted) return;
    if (success) {
      setState(() {
        _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تمييز الكل كمقروء', style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  // ─── حذف القديمة ───
  Future<void> _deleteOld() async {
    final result = await NotificationService.deleteOld(mode: _activeMode);
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف ${result.deleted} إشعار قديم (أقدم من ${result.retentionDays} يوم)',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      _loadNotifications(); // إعادة تحميل
    }
  }

  // ─── أيقونة حسب نوع الإشعار (kind) ───
  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'request_created':
      case 'request_status_change':
        return Icons.assignment;
      case 'offer_created':
      case 'offer_selected':
        return Icons.local_offer;
      case 'message_new':
        return Icons.chat_bubble_outline;
      case 'urgent_request':
        return Icons.warning_amber_rounded;
      case 'success':
        return Icons.check_circle_outline;
      case 'warn':
        return Icons.warning_outlined;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForKind(String kind) {
    switch (kind) {
      case 'urgent_request':
      case 'error':
        return Colors.red;
      case 'offer_created':
      case 'offer_selected':
        return Colors.green;
      case 'message_new':
        return Colors.blue;
      case 'warn':
        return Colors.orange;
      case 'success':
        return Colors.teal;
      default:
        return Colors.deepPurple;
    }
  }

  // ─── تنسيق الوقت ───
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ─── كارت الإشعار ───
  Widget _notificationCard(NotificationModel notif, int index) {
    final bool isUrgent = notif.isUrgent;
    final bool isImportant = notif.isFollowUp;
    final bool isPinned = notif.isPinned;
    final bool isRead = notif.isRead;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUrgent
            ? Colors.red
            : isImportant
                ? const Color(0xFFFFF8E1)
                : isRead
                    ? Colors.grey.shade50
                    : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isImportant
            ? Border.all(color: Colors.amber, width: 2)
            : !isRead
                ? Border.all(color: Colors.deepPurple.shade100, width: 1)
                : Border.all(color: Colors.transparent),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: InkWell(
        onTap: () async {
          // تمييز كمقروء عند النقر
          if (!notif.isRead) {
            await NotificationService.markRead(notif.id, mode: _activeMode);
            setState(() {
              _notifications[index] = notif.copyWith(isRead: true);
            });
          }
          // TODO: التنقل حسب notif.url
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _iconForKind(notif.kind),
              color: isUrgent
                  ? Colors.white
                  : isImportant
                      ? Colors.amber.shade800
                      : _colorForKind(notif.kind),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            fontFamily: "Cairo",
                            fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                            fontSize: 15,
                            color: isUrgent
                                ? Colors.white
                                : isImportant
                                    ? Colors.amber.shade900
                                    : Colors.black87,
                          ),
                        ),
                      ),
                      if (isPinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin, color: Colors.deepPurple, size: 18),
                        ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notif.body,
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 12,
                      color: isUrgent
                          ? Colors.white70
                          : isImportant
                              ? Colors.amber.shade700
                              : Colors.black54,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(notif.createdAt),
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 11,
                      color: isUrgent ? Colors.white60 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),

            // قائمة الخيارات
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: isUrgent ? Colors.white70 : Colors.black54,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) async {
                if (value == 'follow') {
                  final newVal = await NotificationService.toggleFollowUp(notif.id, mode: _activeMode);
                  setState(() {
                    _notifications[index] = notif.copyWith(isFollowUp: newVal);
                  });
                } else if (value == 'pin' || value == 'unpin') {
                  final newVal = await NotificationService.togglePin(notif.id, mode: _activeMode);
                  setState(() {
                    _notifications[index] = notif.copyWith(isPinned: newVal);
                  });
                } else if (value == 'read') {
                  await NotificationService.markRead(notif.id, mode: _activeMode);
                  setState(() {
                    _notifications[index] = notif.copyWith(isRead: true);
                  });
                } else if (value == 'delete') {
                  final success = await NotificationService.deleteNotification(notif.id, mode: _activeMode);
                  if (success) {
                    setState(() {
                      _notifications.removeAt(index);
                    });
                  }
                }
              },
              itemBuilder: (context) => [
                if (!notif.isRead)
                  const PopupMenuItem(value: 'read', child: Text("✓ تمييز كمقروء")),
                PopupMenuItem(
                  value: 'follow',
                  child: Text(notif.isFollowUp ? "⭐ إزالة التمييز" : "⭐ تمييز مهم للمتابعة"),
                ),
                notif.isPinned
                    ? const PopupMenuItem(value: 'unpin', child: Text("❌ إلغاء التثبيت"))
                    : const PopupMenuItem(value: 'pin', child: Text("📌 تثبيت بالأعلى")),
                const PopupMenuItem(value: 'delete', child: Text("🗑 حذف")),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor ?? Colors.deepPurple,
          title: const Text(
            "الإشعارات",
            style: TextStyle(
              fontFamily: "Cairo",
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onSelected: (value) {
                if (value == 'mark_all') _markAllRead();
                if (value == 'delete_old') _deleteOld();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'mark_all', child: Text("✓ تمييز الكل كمقروء")),
                PopupMenuItem(value: 'delete_old', child: Text("🗑 حذف القديمة")),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
                );
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadNotifications,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                          child: const Text("إعادة المحاولة",
                              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                        ),
                      ],
                    ),
                  )
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text("لا توجد إشعارات",
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        color: Colors.deepPurple,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _notifications.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _notifications.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.deepPurple),
                                ),
                              );
                            }
                            return _notificationCard(_notifications[index], index);
                          },
                        ),
                      ),
      ),
    );
  }
}
