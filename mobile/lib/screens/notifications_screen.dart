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

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  List<NotificationModel> _notifications = [];
  String _activeMode = 'client';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _totalCount = 0;
  int _chatUnread = 0;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _entranceController;
  ValueListenable<UnreadBadges>? _badgeHandle;
  StreamSubscription<NotificationRealtimeEvent>? _realtimeSubscription;

  int get _unreadCount =>
      _notifications.where((notification) => !notification.isRead).length;
  int get _followUpCount =>
      _notifications.where((notification) => notification.isFollowUp).length;
  int get _pinnedCount =>
      _notifications.where((notification) => notification.isPinned).length;
  String get _modeLabel => _activeMode == 'provider' ? 'وضع مقدم الخدمة' : 'وضع العميل';

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scrollController.addListener(_onScroll);
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _realtimeSubscription =
        NotificationService.realtimeEvents.listen(_handleRealtimeNotification);
    _handleBadgeChange();
    _initModeAndLoad();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  Future<void> _initModeAndLoad() async {
    final mode = await AccountModeService.apiMode();
    if (!mounted) return;
    setState(() => _activeMode = mode);
    _loadNotifications();
  }

  @override
  void dispose() {
    _entranceController.dispose();
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

  void _handleRealtimeNotification(NotificationRealtimeEvent event) {
    if (!mounted) {
      return;
    }
    if (event is NotificationCreatedRealtimeEvent) {
      final notification = event.notification;
      if (!_matchesActiveMode(notification)) {
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
      return;
    }

    if (event is NotificationDeletedRealtimeEvent) {
      final notificationIds = event.notificationIds.toSet();
      if (notificationIds.isEmpty) {
        return;
      }
      setState(() {
        final before = _notifications.length;
        _notifications.removeWhere((item) => notificationIds.contains(item.id));
        final removed = before - _notifications.length;
        if (removed > 0) {
          _totalCount = (_totalCount - removed).clamp(0, 1 << 30);
        }
      });
    }
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
      if (!mounted) return;
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
    final Color accent = _colorForKind(notif.kind);
    final Color background = isUrgent
        ? const Color(0xFFFFF1F1)
        : isImportant
            ? const Color(0xFFFFF9E8)
            : isRead
                ? const Color(0xFFF9FBFD)
                : Colors.white;
    final Color border = isUrgent
        ? const Color(0xFFF3C0C4)
        : isImportant
            ? const Color(0xFFF2D28D)
            : isRead
                ? const Color(0xFFE4EBF1)
                : accent.withValues(alpha: 0.20);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: isImportant ? 1.4 : 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
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
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: accent.withValues(alpha: 0.11),
              ),
              child: Icon(
                _iconForKind(notif.kind),
                color: accent,
                size: 24,
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
                          notif.title,
                          style: TextStyle(
                            fontFamily: "Cairo",
                            fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                            fontSize: 14,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin,
                              color: accent, size: 16),
                        ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (isUrgent) _buildFlagChip('عاجل', const Color(0xFFB42318), const Color(0xFFFEE4E2)),
                      if (isImportant) _buildFlagChip('متابعة', const Color(0xFF9A6700), const Color(0xFFFFF4CC)),
                      if (isPinned) _buildFlagChip('مثبت', accent, accent.withValues(alpha: 0.12)),
                      if (!isRead) _buildFlagChip('جديد', accent, accent.withValues(alpha: 0.12)),
                    ],
                  ),
                  if (isUrgent || isImportant || isPinned || !isRead)
                    const SizedBox(height: 6),
                  Text(
                    notif.body,
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 11.5,
                      height: 1.8,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF52637A),
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
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF7A8797),
                    ),
                  ),
                ],
              ),
            ),

            // قائمة الخيارات
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: const Color(0xFF708093),
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
    final isDark = theme.brightness == Brightness.dark;
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
        backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
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
        body: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF0E1726), Color(0xFF122235), Color(0xFF17293D)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFEEF5FB), Color(0xFFF4F7FB), Color(0xFFF7F8FC)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: _buildEntrance(0, _buildHeroCard(isDark)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildEntrance(1, _buildControlPanel(isDark)),
              ),
              Expanded(
                child: _isLoading
                    ? _buildLoadingState(isDark)
                    : _errorMessage != null
                        ? _buildErrorState(isDark)
                        : _notifications.isEmpty
                            ? _buildEmptyState(isDark)
                            : RefreshIndicator(
                                onRefresh: _loadNotifications,
                                color: const Color(0xFF0E7490),
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                                  itemCount:
                                      _notifications.length + (_isLoadingMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _notifications.length) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF0E7490),
                                          ),
                                        ),
                                      );
                                    }
                                    return _notificationCard(_notifications[index], index);
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0E7490), Color(0xFF1D4ED8)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -42,
            left: -18,
            child: Container(
              width: 134,
              height: 134,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -54,
            right: -20,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBadge(_modeLabel),
              const SizedBox(height: 12),
              const Text(
                'الإشعارات',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'تابع آخر التحديثات والعروض والرسائل في مكان واحد، مع وصول أسرع للأهم أولاً وإدارة أوضح للحالات المقروءة.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatChip('الإجمالي', '$_totalCount'),
                  _buildStatChip('غير المقروء', '$_unreadCount'),
                  _buildStatChip('للمتابعة', '$_followUpCount'),
                  _buildStatChip('مثبت', '$_pinnedCount'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x220E5E85),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'لوحة التحكم',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'إعدادات سريعة لإدارة كل الإشعارات، تمييز المقروء، وتنظيف السجل القديم.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionButton(
                label: 'إعدادات الإشعارات',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'تمييز الكل كمقروء',
                onTap: _markAllRead,
              ),
              _buildActionButton(
                label: 'حذف القديم',
                onTap: _deleteOld,
                danger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
      children: List.generate(4, (_) => _buildLoadingCard(isDark)),
    );
  }

  Widget _buildLoadingCard(bool isDark) {
    final baseColor = isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94);
    final lineColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EEF3);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lineColor),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: 150, color: lineColor),
                const SizedBox(height: 10),
                Container(height: 10, width: double.infinity, color: lineColor),
                const SizedBox(height: 6),
                Container(height: 10, width: 180, color: lineColor),
                const SizedBox(height: 10),
                Container(height: 8, width: 80, color: lineColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0x220E5E85),
            ),
          ),
          child: Column(
            children: [
              Icon(Icons.error_outline_rounded, size: 44, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'فشل تحميل الإشعارات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : const Color(0xFF52637A),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _loadNotifications,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E7490),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0x220E5E85),
            ),
          ),
          child: Column(
            children: [
              Icon(Icons.notifications_off_outlined,
                  size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(
                'لا توجد إشعارات حالياً',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ستظهر هنا الرسائل والتحديثات والعروض والتنبيهات الجديدة بمجرد وصولها إلى حسابك.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.8,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? Colors.red.shade700 : const Color(0xFF0E7490),
        side: BorderSide(
          color: danger ? const Color(0xFFF3C0C4) : const Color(0xFFCCE0F8),
        ),
        backgroundColor: danger ? const Color(0xFFFFF3F4) : const Color(0xFFF4F8FF),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildHeaderBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.94),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlagChip(String label, Color color, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.08 * index).clamp(0.0, 0.8).toDouble();
    final end = (begin + 0.34).clamp(0.0, 1.0).toDouble();
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
