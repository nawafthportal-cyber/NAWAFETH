import 'package:flutter/material.dart';
import 'notification_settings_screen.dart'; // ✅ صفحة الإعدادات
import '../utils/auth_guard.dart';
import '../models/app_notification.dart';
import '../services/notifications_api.dart';
import '../services/notifications_badge_controller.dart';
import '../services/notification_link_handler.dart';
import '../services/role_controller.dart';
import '../services/session_storage.dart';
import 'notification_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = NotificationsApi();
  final _scroll = ScrollController();
  final _session = const SessionStorage();

  final List<AppNotification> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;
  bool _loginRequired = false;
  int? _lastUnreadCount;
  bool _showNewNotificationsBanner = false;

  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final loggedIn = await _session.isLoggedIn();
      if (!loggedIn) {
        setState(() {
          _loading = false;
          _error = 'تسجيل الدخول مطلوب';
          _loginRequired = true;
        });
        return;
      }
      await _loadInitial();
    });
    _scroll.addListener(_onScroll);
    RoleController.instance.notifier.addListener(_onRoleChanged);
    NotificationsBadgeController.instance.unreadNotifier.addListener(_onUnreadChanged);
    _lastUnreadCount = NotificationsBadgeController.instance.unreadNotifier.value;
  }

  @override
  void dispose() {
    RoleController.instance.notifier.removeListener(_onRoleChanged);
    NotificationsBadgeController.instance.unreadNotifier.removeListener(_onUnreadChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onRoleChanged() {
    // Refresh list when switching client/provider.
    _loadInitial();
  }

  void _onUnreadChanged() {
    final current = NotificationsBadgeController.instance.unreadNotifier.value;
    final previous = _lastUnreadCount;
    _lastUnreadCount = current;
    if (current == null) return;
    if (previous == null) return;
    if (current <= previous) return;
    _refreshTopSilently();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    final loggedIn = await _session.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تسجيل الدخول مطلوب';
        _loginRequired = true;
        _items.clear();
        _offset = 0;
        _hasMore = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _loginRequired = false;
      _items.clear();
      _offset = 0;
      _hasMore = true;
    });

    try {
      final page = await _api.list(limit: _limit, offset: 0);
      final results = (page['results'] as List?) ?? const [];
      final items = results
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _offset = _items.length;
        _hasMore = items.length >= _limit;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل الإشعارات';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore) return;
    final loggedIn = await _session.isLoggedIn();
    if (!loggedIn) return;
    setState(() {
      _loadingMore = true;
    });

    try {
      final page = await _api.list(limit: _limit, offset: _offset);
      final results = (page['results'] as List?) ?? const [];
      final items = results
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _offset = _items.length;
        _hasMore = items.length >= _limit;
      });
    } catch (_) {
      // Ignore load-more errors; user can pull-to-refresh.
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm • $y/$m/$d';
  }

  IconData _iconForKind(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'review_reply':
        return Icons.rate_review_outlined;
      case 'urgent_request':
        return Icons.bolt_rounded;
      case 'offer_created':
        return Icons.local_offer_outlined;
      case 'offer_selected':
        return Icons.task_alt_rounded;
      case 'request_status_change':
        return Icons.sync_alt_rounded;
      case 'report_status_change':
        return Icons.support_agent_rounded;
      case 'message_new':
      case 'message':
      case 'chat':
      case 'chat_message':
        return Icons.chat_bubble_outline;
      case 'urgent':
        return Icons.warning_amber_rounded;
      case 'info':
      default:
        return Icons.notifications_none;
    }
  }

  String? _kindLabel(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'review_reply':
        return 'رد على مراجعتك';
      case 'urgent_request':
        return 'طلب عاجل';
      case 'offer_created':
        return 'عرض جديد';
      case 'offer_selected':
        return 'تم اختيار عرضك';
      case 'request_status_change':
        return 'تحديث الطلب';
      case 'report_status_change':
        return 'تحديث البلاغ';
      case 'message':
      case 'message_new':
      case 'chat':
      case 'chat_message':
        return 'رسالة';
      case 'urgent':
        return 'عاجل';
      default:
        return null;
    }
  }

  Future<void> _refreshTopSilently() async {
    if (_loading || _loadingMore) return;
    try {
      final previousTopId = _items.isNotEmpty ? _items.first.id : -1;
      final page = await _api.list(limit: _limit, offset: 0);
      final results = (page['results'] as List?) ?? const [];
      final fresh = results
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted || fresh.isEmpty) return;

      final merged = <AppNotification>[...fresh];
      final existingIds = fresh.map((e) => e.id).toSet();
      for (final old in _items) {
        if (!existingIds.contains(old.id)) {
          merged.add(old);
        }
      }

      merged.sort((a, b) {
        final ap = (a.isPinned ? 2 : 0) + (a.isUrgent ? 1 : 0);
        final bp = (b.isPinned ? 2 : 0) + (b.isUrgent ? 1 : 0);
        if (ap != bp) return bp.compareTo(ap);
        return b.id.compareTo(a.id);
      });

      setState(() {
        _items
          ..clear()
          ..addAll(merged);
        _offset = _items.length;
        _hasMore = fresh.length >= _limit;
        if (_items.isNotEmpty && _items.first.id > previousTopId) {
          _showNewNotificationsBanner = true;
        }
      });
    } catch (_) {
      // Best-effort live refresh.
    }
  }

  Widget _newNotificationsBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'وصلت تنبيهات جديدة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              setState(() => _showNewNotificationsBanner = false);
              if (_scroll.hasClients) {
                await _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                );
              }
            },
            child: const Text(
              'عرض الآن',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _showNewNotificationsBanner = false),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePin(AppNotification notification) async {
    await _api.togglePin(notification.id);
    if (!mounted) return;
    setState(() {
      final idx = _items.indexWhere((n) => n.id == notification.id);
      if (idx >= 0) {
        final n = _items[idx];
        _items[idx] = AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          kind: n.kind,
          url: n.url,
          isRead: n.isRead,
          isPinned: !n.isPinned,
          isFollowUp: n.isFollowUp,
          isUrgent: n.isUrgent,
          createdAt: n.createdAt,
        );
      }
    });
    _items.sort((a, b) {
      final ap = (a.isPinned ? 2 : 0) + (a.isUrgent ? 1 : 0);
      final bp = (b.isPinned ? 2 : 0) + (b.isUrgent ? 1 : 0);
      if (ap != bp) return bp.compareTo(ap);
      return b.id.compareTo(a.id);
    });
  }

  Future<void> _toggleFollowUp(AppNotification notification) async {
    await _api.toggleFollowUp(notification.id);
    if (!mounted) return;
    setState(() {
      final idx = _items.indexWhere((n) => n.id == notification.id);
      if (idx >= 0) {
        final n = _items[idx];
        _items[idx] = AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          kind: n.kind,
          url: n.url,
          isRead: n.isRead,
          isPinned: n.isPinned,
          isFollowUp: !n.isFollowUp,
          isUrgent: n.isUrgent,
          createdAt: n.createdAt,
        );
      }
    });
  }

  Future<void> _deleteNotification(AppNotification notification) async {
    await _api.deleteNotification(notification.id);
    if (!mounted) return;
    setState(() {
      _items.removeWhere((n) => n.id == notification.id);
    });
  }

  Future<void> _markAllRead() async {
    final loggedIn = await _session.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      await checkAuth(context);
      return;
    }

    try {
      await _api.markAllRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          final n = _items[i];
          if (!n.isRead) {
            _items[i] = AppNotification(
              id: n.id,
              title: n.title,
              body: n.body,
              kind: n.kind,
              url: n.url,
              isRead: true,
              isPinned: n.isPinned,
              isFollowUp: n.isFollowUp,
              isUrgent: n.isUrgent,
              createdAt: n.createdAt,
            );
          }
        }
      });
      NotificationsBadgeController.instance.refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تعليم الكل كمقروء')),
      );
    }
  }

  Future<void> _markReadIfNeeded(AppNotification notification) async {
    if (notification.isRead) return;
    await _api.markRead(notification.id);
    if (!mounted) return;
    setState(() {
      final idx = _items.indexWhere((n) => n.id == notification.id);
      if (idx >= 0) {
        final n = _items[idx];
        _items[idx] = AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          kind: n.kind,
          url: n.url,
          isRead: true,
          isPinned: n.isPinned,
          isFollowUp: n.isFollowUp,
          isUrgent: n.isUrgent,
          createdAt: n.createdAt,
        );
      }
    });
    NotificationsBadgeController.instance.refresh();
  }

  Widget _notificationCard(AppNotification notification) {
    final isUnread = !notification.isRead;
    final theme = Theme.of(context);
    final bg = notification.isUrgent
        ? theme.colorScheme.error.withValues(alpha: 0.06)
        : theme.cardColor;

    return InkWell(
      onTap: () async {
        try {
          await _markReadIfNeeded(notification);
          if (!mounted) return;

          final opened = await NotificationLinkHandler.openFromNotification(
            context,
            notification,
          );
          if (!mounted) return;
          if (!opened) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotificationDetailsScreen(notification: notification),
              ),
            );
          }
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر تعليم الإشعار كمقروء')),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnread
                ? theme.colorScheme.primary.withValues(alpha: 0.35)
                : Colors.transparent,
            width: isUnread ? 1.2 : 1,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconForKind(notification.kind),
                color: theme.colorScheme.primary,
                size: 22,
              ),
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
                          notification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          try {
                            if (value == 'follow_up') {
                              await _toggleFollowUp(notification);
                            } else if (value == 'pin') {
                              await _togglePin(notification);
                            } else if (value == 'delete') {
                              await _deleteNotification(notification);
                            }
                          } catch (_) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تعذر تنفيذ الإجراء')),
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'follow_up',
                            child: Text(
                              notification.isFollowUp ? 'إلغاء المتابعة' : 'تمييز للمتابعة',
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'pin',
                            child: Text(
                              notification.isPinned ? 'إلغاء التثبيت' : 'تثبيت بالأعلى',
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
                          ),
                        ],
                      ),
                      if (isUnread)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (notification.isPinned || notification.isFollowUp || notification.isUrgent) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (notification.isUrgent)
                          _flagChip('عاجل', theme.colorScheme.error),
                        if (notification.isPinned)
                          _flagChip('مثبّت', theme.colorScheme.primary),
                        if (notification.isFollowUp)
                          _flagChip('للمتابعة', Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  if ((_kindLabel(notification.kind) ?? '').isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _flagChip(
                          _kindLabel(notification.kind)!,
                          theme.colorScheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    notification.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _formatDate(notification.createdAt.toLocal()),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.70),
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
            IconButton(
              tooltip: 'تعليم الكل كمقروء',
              icon: const Icon(Icons.done_all, color: Colors.white),
              onPressed: () async {
                await _markAllRead();
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () async {
                if (!await checkFullClient(context)) return;
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadInitial,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: ElevatedButton(
                            onPressed: _loginRequired
                                ? () => checkAuth(context)
                                : _loadInitial,
                            child: Text(
                              _loginRequired ? 'دخول' : 'إعادة المحاولة',
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        ),
                      ],
                    )
                  : (_items.isEmpty)
                      ? ListView(
                          children: const [
                            SizedBox(height: 140),
                            Center(
                              child: Text(
                                'لا توجد إشعارات حالياً',
                                style: TextStyle(fontFamily: 'Cairo'),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length + (_loadingMore ? 1 : 0) + (_showNewNotificationsBanner ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_showNewNotificationsBanner && index == 0) {
                              return _newNotificationsBanner();
                            }
                            final adjustedIndex = index - (_showNewNotificationsBanner ? 1 : 0);
                            if (adjustedIndex >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return _notificationCard(_items[adjustedIndex]);
                          },
                        ),
        ),
      ),
    );
  }

  Widget _flagChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
