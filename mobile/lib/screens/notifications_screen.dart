// ignore_for_file: unused_field
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_model.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../services/account_mode_service.dart';
import '../services/unread_badge_service.dart';
import '../widgets/platform_top_bar.dart';
import 'chat_detail_screen.dart';
import 'client_order_details_screen.dart';
import 'contact_screen.dart';
import 'my_chats_screen.dart';
import 'notification_settings_screen.dart';
import 'plans_screen.dart';
import 'provider_dashboard/promotion_screen.dart';
import 'provider_dashboard/provider_order_details_screen.dart';
import 'provider_profile_screen.dart';
import 'verification_screen.dart';

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
  int _chatUnread = 0;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  ValueListenable<UnreadBadges>? _badgeHandle;
  StreamSubscription<NotificationModel>? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _realtimeSubscription =
        NotificationService.realtimeEvents.listen(_handleRealtimeNotification);
    _handleBadgeChange();
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
    _realtimeSubscription?.cancel();
    if (_badgeHandle != null) {
      _badgeHandle?.removeListener(_handleBadgeChange);
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeHandle?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _chatUnread = badges.chats;
    });
  }

  bool _matchesActiveMode(NotificationModel notification) {
    return notification.audienceMode == 'shared' ||
        notification.audienceMode == _activeMode;
  }

  void _handleRealtimeNotification(NotificationModel notification) {
    if (!_matchesActiveMode(notification) || !mounted) {
      return;
    }
    setState(() {
      final existingIndex =
          _notifications.indexWhere((item) => item.id == notification.id);
      if (existingIndex >= 0) {
        _notifications.removeAt(existingIndex);
      } else {
        _totalCount += 1;
      }
      _notifications.insert(0, notification);
      _errorMessage = null;
      _isLoading = false;
    });
  }

  String _normalizePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  Uri? _tryParseNotificationUri(String rawUrl) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
    if (raw.startsWith('/')) {
      return Uri.tryParse('https://local.invalid$raw');
    }
    return Uri.tryParse('https://local.invalid/$raw');
  }

  bool _isPromoPreviewLink(
      {required String normalizedPath, required Uri? uri}) {
    if (normalizedPath != '/notifications' &&
        normalizedPath != '/notifications/') {
      return false;
    }
    return (uri?.queryParameters['promo_item_id'] ?? '').trim().isNotEmpty;
  }

  Widget? _destinationForNotification({
    required String path,
    required String normalizedPath,
    required Uri? uri,
  }) {
    if (normalizedPath == '/contact' || normalizedPath == '/contact/') {
      final ticketId =
          int.tryParse((uri?.queryParameters['ticket'] ?? '').trim());
      if (ticketId != null) {
        return ContactScreen(initialTicketId: ticketId);
      }
      return const ContactScreen();
    }

    final supportTicketMatch =
        RegExp(r'^/support/tickets/(\d+)/?$', caseSensitive: false)
            .firstMatch(path);
    if (supportTicketMatch != null) {
      final ticketId = int.tryParse(supportTicketMatch.group(1) ?? '');
      if (ticketId != null) {
        return ContactScreen(initialTicketId: ticketId);
      }
    }

    final requestChatMatch =
        RegExp(r'^/requests/(\d+)/chat/?$', caseSensitive: false)
            .firstMatch(path);
    if (requestChatMatch != null) {
      final requestId = int.tryParse(requestChatMatch.group(1) ?? '');
      if (requestId != null) {
        return _activeMode == 'provider'
            ? ProviderOrderDetailsScreen(requestId: requestId)
            : ClientOrderDetailsScreen(requestId: requestId);
      }
    }

    final requestMatch =
        RegExp(r'^/requests/(\d+)/?$', caseSensitive: false).firstMatch(path);
    if (requestMatch != null) {
      final requestId = int.tryParse(requestMatch.group(1) ?? '');
      if (requestId != null) {
        return _activeMode == 'provider'
            ? ProviderOrderDetailsScreen(requestId: requestId)
            : ClientOrderDetailsScreen(requestId: requestId);
      }
    }

    final threadMatch =
        RegExp(r'^/(?:threads|chat)/(\d+)(?:/chat)?/?$', caseSensitive: false)
            .firstMatch(path);
    if (threadMatch != null) {
      final threadId = int.tryParse(threadMatch.group(1) ?? '');
      if (threadId != null) {
        return ChatDetailScreen(
          threadId: threadId,
          peerName: 'المحادثة',
        );
      }
    }

    if (normalizedPath == '/plans' || normalizedPath == '/plans/') {
      return const PlansScreen();
    }

    if (normalizedPath == '/verification' ||
        normalizedPath == '/verification/') {
      return const VerificationScreen();
    }

    if (normalizedPath == '/promotion' || normalizedPath == '/promotion/') {
      return const PromotionScreen();
    }

    final providerProfileMatch =
        RegExp(r'^/provider/(\d+)/?$', caseSensitive: false).firstMatch(path);
    if (providerProfileMatch != null) {
      final providerId = int.tryParse(providerProfileMatch.group(1) ?? '');
      if (providerId != null) {
        return ProviderProfileScreen(providerId: providerId.toString());
      }
    }

    return null;
  }

  Uri? _resolveExternalUri(String rawUrl) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) return null;

    final parsed = Uri.tryParse(raw);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      return parsed;
    }

    try {
      final base = Uri.parse(ApiClient.baseUrl);
      final relative = raw.startsWith('/') ? raw : '/$raw';
      return base.resolve(relative);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _openExternalUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _showPromoPreview(NotificationModel notification) async {
    final payload =
        await NotificationService.fetchPromoPreview(notification.id);
    if (!mounted || payload == null) {
      return false;
    }

    final title = (payload['title'] as String? ?? notification.title).trim();
    final body = (payload['body'] as String? ?? notification.body).trim();
    final attachments = (payload['attachments'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          title.isEmpty ? 'رسالة دعائية' : title,
          style:
              const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (body.isNotEmpty)
                  Text(
                    body,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  ),
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'المرفقات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final attachment in attachments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.attachment_outlined),
                      title: Text(
                        (attachment['title'] as String?)?.trim().isNotEmpty ==
                                true
                            ? (attachment['title'] as String).trim()
                            : ((attachment['file_name'] as String?) ?? 'مرفق'),
                        style:
                            const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      ),
                      subtitle: Text(
                        (attachment['asset_type'] as String? ?? '').trim(),
                        style:
                            const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new_rounded),
                        onPressed: () async {
                          final fileUrl =
                              (attachment['file_url'] as String? ?? '').trim();
                          final fileUri = _resolveExternalUri(fileUrl);
                          if (fileUri == null) return;
                          await _openExternalUri(fileUri);
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    return true;
  }

  Future<void> _openNotification(NotificationModel notification) async {
    final rawUrl = (notification.url ?? '').trim();
    if (rawUrl.isEmpty) {
      return;
    }

    final uri = _tryParseNotificationUri(rawUrl);
    final path = _normalizePath((uri?.path ?? rawUrl).trim());
    final normalizedPath = path.toLowerCase();

    if (_isPromoPreviewLink(normalizedPath: normalizedPath, uri: uri)) {
      final opened = await _showPromoPreview(notification);
      if (opened) {
        await UnreadBadgeService.refresh(force: true);
        return;
      }
    }

    final destination = _destinationForNotification(
      path: path,
      normalizedPath: normalizedPath,
      uri: uri,
    );
    if (destination != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
      await UnreadBadgeService.refresh(force: true);
      return;
    }

    final externalUri = _resolveExternalUri(rawUrl);
    if (externalUri != null && await _openExternalUri(externalUri)) {
      await UnreadBadgeService.refresh(force: true);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'لا يوجد مسار متاح لهذا الإشعار حاليًا',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final page =
          await NotificationService.fetchNotifications(mode: _activeMode);
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
        _notifications =
            _notifications.map((n) => n.copyWith(isRead: true)).toList();
      });
      await UnreadBadgeService.refresh(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تمييز الكل كمقروء',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  // ─── حذف القديمة ───
  Future<void> _deleteOld() async {
    final result = await NotificationService.deleteOld(mode: _activeMode);
    if (!mounted) return;
    if (result.success) {
      await UnreadBadgeService.refresh(force: true);
      if (!mounted) return;
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
            if (!mounted) return;
            setState(() {
              _notifications[index] = notif.copyWith(isRead: true);
            });
            unawaited(UnreadBadgeService.refresh(force: true));
          }
          await _openNotification(notif);
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
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.bold,
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
                          child: Icon(Icons.push_pin,
                              color: Colors.deepPurple, size: 18),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (value) async {
                if (value == 'follow') {
                  final newVal = await NotificationService.toggleFollowUp(
                      notif.id,
                      mode: _activeMode);
                  setState(() {
                    _notifications[index] = notif.copyWith(isFollowUp: newVal);
                  });
                } else if (value == 'pin' || value == 'unpin') {
                  final newVal = await NotificationService.togglePin(notif.id,
                      mode: _activeMode);
                  setState(() {
                    _notifications[index] = notif.copyWith(isPinned: newVal);
                  });
                } else if (value == 'read') {
                  await NotificationService.markRead(notif.id,
                      mode: _activeMode);
                  setState(() {
                    _notifications[index] = notif.copyWith(isRead: true);
                  });
                  unawaited(UnreadBadgeService.refresh(force: true));
                } else if (value == 'delete') {
                  final success = await NotificationService.deleteNotification(
                      notif.id,
                      mode: _activeMode);
                  if (success) {
                    setState(() {
                      _notifications.removeAt(index);
                      if (_totalCount > 0) {
                        _totalCount -= 1;
                      }
                    });
                    unawaited(UnreadBadgeService.refresh(force: true));
                  }
                }
              },
              itemBuilder: (context) => [
                if (!notif.isRead)
                  const PopupMenuItem(
                      value: 'read', child: Text("✓ تمييز كمقروء")),
                PopupMenuItem(
                  value: 'follow',
                  child: Text(notif.isFollowUp
                      ? "⭐ إزالة التمييز"
                      : "⭐ تمييز مهم للمتابعة"),
                ),
                notif.isPinned
                    ? const PopupMenuItem(
                        value: 'unpin', child: Text("❌ إلغاء التثبيت"))
                    : const PopupMenuItem(
                        value: 'pin', child: Text("📌 تثبيت بالأعلى")),
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
    final bool canPop = Navigator.of(context).canPop();
    final foreground = theme.brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF56316D);
    final chromeBackground = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.82);
    final chromeBorder = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFDACDED);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PlatformTopBar(
          pageLabel: 'الإشعارات',
          showBackButton: canPop,
          showNotificationAction: false,
          chatCount: _chatUnread,
          onChatsTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MyChatsScreen(),
              ),
            );
            await UnreadBadgeService.refresh(force: true);
          },
          trailingActions: [
            PlatformTopBarMenuButton<String>(
              icon: Icons.more_horiz_rounded,
              foreground: foreground,
              background: chromeBackground,
              borderColor: chromeBorder,
              onSelected: (value) {
                if (value == 'mark_all') _markAllRead();
                if (value == 'delete_old') _deleteOld();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'mark_all',
                  child: Text('✓ تمييز الكل كمقروء'),
                ),
                PopupMenuItem(
                  value: 'delete_old',
                  child: Text('🗑 حذف القديمة'),
                ),
              ],
            ),
            const SizedBox(width: 6),
            PlatformTopBarActionButton(
              icon: Icons.settings_outlined,
              foreground: foreground,
              background: chromeBackground,
              borderColor: chromeBorder,
              onTap: () {
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
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple))
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_errorMessage!,
                            style: const TextStyle(
                                fontFamily: 'Cairo', color: Colors.grey)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadNotifications,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple),
                          child: const Text("إعادة المحاولة",
                              style: TextStyle(
                                  fontFamily: 'Cairo', color: Colors.white)),
                        ),
                      ],
                    ),
                  )
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_off_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text("لا توجد إشعارات",
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 16,
                                    color: Colors.grey)),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text(
                              'تابع آخر التحديثات والعروض والرسائل في مكان واحد.',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _loadNotifications,
                              color: Colors.deepPurple,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: _notifications.length +
                                    (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _notifications.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.deepPurple),
                                      ),
                                    );
                                  }
                                  return _notificationCard(
                                      _notifications[index], index);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
