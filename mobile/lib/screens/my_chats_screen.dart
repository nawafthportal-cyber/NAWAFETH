import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/chat_thread_model.dart';
import '../services/account_mode_service.dart';
import '../services/api_client.dart';
import '../services/messaging_service.dart';
import '../services/unread_badge_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/excellence_badges_wrap.dart';
import '../widgets/platform_top_bar.dart';
import 'chat_detail_screen.dart';

class MyChatsScreen extends StatefulWidget {
  const MyChatsScreen({super.key});

  @override
  State<MyChatsScreen> createState() => _MyChatsScreenState();
}

class _MyChatsScreenState extends State<MyChatsScreen>
    with SingleTickerProviderStateMixin {
  String selectedFilter = 'الكل';
  String searchQuery = '';

  bool _isProviderAccount = false;
  bool _isLoading = true;
  String? _errorMessage;

  List<ChatThread> _threads = [];
  late final TextEditingController _searchController;
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderAccount = isProvider;
      if (!_isProviderAccount && selectedFilter == 'عملاء') {
        selectedFilter = 'الكل';
      }
    });
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
      _entranceController
        ..reset()
        ..forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل المحادثات';
      });
    }
  }

  List<ChatThread> get _visibleThreads {
    return _threads.where((thread) => !thread.isBlocked && !thread.isArchived).toList();
  }

  int get _totalUnreadMessages {
    return _visibleThreads.fold<int>(0, (sum, thread) => sum + thread.unreadCount);
  }

  int get _unreadThreadsCount {
    return _visibleThreads.where((thread) => thread.unreadCount > 0).length;
  }

  int get _favoriteThreadsCount {
    return _visibleThreads.where((thread) => thread.isFavorite).length;
  }

  int get _clientsThreadsCount {
    return _visibleThreads.where((thread) => (thread.clientLabel ?? '').trim().isNotEmpty).length;
  }

  String get _modeLabel => _isProviderAccount ? 'وضع مقدم الخدمة' : 'وضع العميل';

  List<ChatThread> getFilteredChats() {
    List<ChatThread> filtered = [..._visibleThreads];

    if (searchQuery.trim().isNotEmpty) {
      final query = searchQuery.trim();
      filtered = filtered.where((thread) {
        return thread.peerDisplayName.contains(query) ||
            thread.peerPhone.contains(query) ||
            thread.peerLocationDisplay.contains(query);
      }).toList();
    }

    if (selectedFilter == 'غير مقروءة') {
      filtered = filtered.where((thread) => thread.unreadCount > 0).toList();
    } else if (selectedFilter == 'مفضلة') {
      filtered = filtered.where((thread) => thread.isFavorite).toList();
    } else if (selectedFilter == 'عملاء') {
      if (_isProviderAccount) {
        filtered = filtered
            .where((thread) => (thread.clientLabel ?? '').trim().isNotEmpty)
            .toList();
      }
    } else if (selectedFilter == 'الأحدث') {
      filtered.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return filtered;
    }

    filtered.sort((a, b) {
      if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
      if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
    return filtered;
  }

  String _threadPreviewText(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return 'لا توجد رسائل بعد';
    final hasServiceRequestLink = RegExp(
      r'(https?:\/\/\S+|\/service-request\/\S*)',
      caseSensitive: false,
    ).hasMatch(text);
    if (hasServiceRequestLink &&
        text.toLowerCase().contains('service-request') &&
        RegExp(r'provider_id=\d+', caseSensitive: false).hasMatch(text)) {
      return '🛠️ طلب خدمة مباشر';
    }
    return text;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} د';
    if (diff.inDays < 1) {
      final hour24 = dt.hour;
      final hour = hour24 > 12 ? hour24 - 12 : hour24;
      final amPm = hour24 >= 12 ? 'م' : 'ص';
      final minutes = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minutes $amPm';
    }
    if (diff.inDays == 1) return 'الأمس';
    if (diff.inDays < 7) {
      const days = [
        'الإثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد',
      ];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  bool _meaningfulValue(String? value) => (value ?? '').trim().isNotEmpty;

  bool _isPlatformTeamName(String name) => name.trim().startsWith('فريق ');

  _ThreadKind _threadKind(ChatThread thread) {
    final displayName = thread.peerDisplayName;
    if (_isPlatformTeamName(displayName)) return _ThreadKind.team;
    if ((thread.peerProviderId ?? 0) > 0) return _ThreadKind.provider;
    if (_isProviderAccount) return _ThreadKind.client;
    return _ThreadKind.member;
  }

  String _threadRoleLabel(_ThreadKind kind) {
    switch (kind) {
      case _ThreadKind.team:
        return 'فريق المنصة';
      case _ThreadKind.provider:
        return 'مزود خدمة';
      case _ThreadKind.client:
        return 'عميل';
      case _ThreadKind.member:
        return '';
    }
  }

  String _threadSubtitle(ChatThread thread, _ThreadKind kind) {
    switch (kind) {
      case _ThreadKind.team:
        return 'متابعة مباشرة مع فريق المنصة';
      case _ThreadKind.provider:
        return _meaningfulValue(thread.peerLocationDisplay)
            ? 'مقدم خدمة في ${thread.peerLocationDisplay}'
            : 'مقدم خدمة على المنصة';
      case _ThreadKind.client:
        return _meaningfulValue(thread.clientLabel)
            ? thread.clientLabel!.trim()
            : 'عميل يتابع معك مباشرة';
      case _ThreadKind.member:
        return 'رسائل مباشرة داخل نوافذ';
    }
  }

  _PreviewTone _threadPreviewTone(ChatThread thread, _ThreadKind kind) {
    final preview = _threadPreviewText(thread.lastMessage);
    if (kind == _ThreadKind.team) return _PreviewTone.team;
    if (preview.startsWith('🛠️')) return _PreviewTone.service;
    return _PreviewTone.defaultTone;
  }

  _PreviewLabel? _threadPreviewLabel(_PreviewTone tone, _ThreadKind kind) {
    if (tone == _PreviewTone.team) {
      return const _PreviewLabel('رسالة فريق', Color(0xFFEDE9FE), Color(0xFF6D28D9));
    }
    if (tone == _PreviewTone.service) {
      return const _PreviewLabel('طلب خدمة', Color(0xFFFFF4CC), Color(0xFF9A6700));
    }
    if (kind == _ThreadKind.provider) {
      return const _PreviewLabel('مباشر', Color(0xFFE0F2FE), Color(0xFF0369A1));
    }
    return null;
  }

  Future<void> _openThread(ChatThread thread) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          threadId: thread.threadId,
          peerName: thread.peerDisplayName,
          peerPhone: thread.peerPhone,
          peerCity: thread.peerLocationDisplay,
          peerId: thread.peerId,
          peerProviderId: thread.peerProviderId,
        ),
      ),
    );
    await _fetchThreads();
    unawaited(UnreadBadgeService.refresh(force: true));
  }

  void _showChatOptions(ChatThread thread) {
    final isUnread = thread.unreadCount > 0;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.peerDisplayName,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _threadSubtitle(thread, _threadKind(thread)),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionSheetItem(
                  icon: isUnread
                      ? Icons.mark_email_read_outlined
                      : Icons.mark_chat_unread_outlined,
                  label: isUnread ? 'اجعلها مقروءة' : 'اجعلها غير مقروءة',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (isUnread) {
                      await MessagingService.markRead(thread.threadId);
                    } else {
                      await MessagingService.markUnread(thread.threadId);
                    }
                    await _fetchThreads();
                    unawaited(UnreadBadgeService.refresh(force: true));
                  },
                ),
                _buildActionSheetItem(
                  icon: Icons.star_outline_rounded,
                  label: thread.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await MessagingService.toggleFavorite(
                      thread.threadId,
                      remove: thread.isFavorite,
                    );
                    await _fetchThreads();
                  },
                ),
                _buildActionSheetItem(
                  icon: thread.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                  label: thread.isBlocked ? 'إلغاء الحظر' : 'حظر',
                  danger: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await MessagingService.toggleBlock(
                      thread.threadId,
                      remove: thread.isBlocked,
                    );
                    await _fetchThreads();
                  },
                ),
                _buildActionSheetItem(
                  icon: Icons.report_gmailerrorred_rounded,
                  label: 'إبلاغ',
                  danger: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showReportDialog(thread);
                  },
                ),
                _buildActionSheetItem(
                  icon: Icons.archive_outlined,
                  label: 'أرشفة',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await MessagingService.toggleArchive(thread.threadId);
                    await _fetchThreads();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionSheetItem({
    required IconData icon,
    required String label,
    required FutureOr<void> Function() onTap,
    bool danger = false,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFFF1F1) : const Color(0xFFF4F4FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: danger ? const Color(0xFFB42318) : const Color(0xFF5B3FD0),
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: danger ? const Color(0xFFB42318) : const Color(0xFF0F172A),
        ),
      ),
      onTap: () async => onTap(),
    );
  }

  void _showReportDialog(ChatThread thread) {
    final reasonController = TextEditingController();
    String selectedReason = 'محتوى غير لائق';
    bool isSending = false;

    final reasons = const [
      'محتوى غير لائق',
      'احتيال أو نصب',
      'إزعاج أو مضايقة',
      'انتحال شخصية',
      'محتوى مخالف للشروط',
      'أخرى',
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.report_gmailerrorred_rounded,
                        color: Color(0xFFB54708),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'إبلاغ عن محادثة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    thread.peerDisplayName,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'سبب الإبلاغ',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFFCFCFD),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                      ),
                    ),
                    items: reasons
                        .map(
                          (reason) => DropdownMenuItem<String>(
                            value: reason,
                            child: Text(
                              reason,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedReason = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'تفاصيل إضافية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'اكتب التفاصيل هنا...',
                      hintStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF98A2B3),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFFCFCFD),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF667085),
                  ),
                ),
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
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.success
                                  ? 'تم إرسال البلاغ للإدارة. شكراً لك'
                                  : result.error ?? 'فشل إرسال البلاغ',
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor:
                                result.success ? const Color(0xFF1B8A5A) : const Color(0xFFB42318),
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB54708),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: isSending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'إرسال البلاغ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _filterCount(String label) {
    switch (label) {
      case 'الكل':
        return _visibleThreads.length;
      case 'غير مقروءة':
        return _unreadThreadsCount;
      case 'مفضلة':
        return _favoriteThreadsCount;
      case 'عملاء':
        return _clientsThreadsCount;
      case 'الأحدث':
        return _visibleThreads.length;
      default:
        return 0;
    }
  }

  String _emptyMessage() {
    if (searchQuery.trim().isNotEmpty) return 'لا توجد نتائج مطابقة للبحث.';

    switch (selectedFilter) {
      case 'غير مقروءة':
        return 'لا توجد رسائل غير مقروءة.';
      case 'مفضلة':
        return 'لا توجد رسائل مفضلة.';
      case 'عملاء':
        return 'لا توجد رسائل عملاء حالياً.';
      case 'الأحدث':
        return 'لا توجد رسائل حديثة حالياً.';
      default:
        return 'لا توجد رسائل بعد.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedChats = getFilteredChats();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
      drawer: const CustomDrawer(),
      appBar: const PlatformTopBar(
        pageLabel: 'محادثاتي',
        showNotificationAction: false,
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
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: _buildEntrance(0, _buildHeroCard(isDark)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildEntrance(1, _buildControlPanel(isDark, sortedChats.length)),
              ),
              Expanded(
                child: _buildBody(isDark, sortedChats),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: -1),
    );
  }

  Widget _buildHeroCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF183B64), Color(0xFF22577A), Color(0xFF0F766E)],
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
            top: -44,
            left: -18,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -56,
            right: -24,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroTagChip(label: _modeLabel),
              const SizedBox(height: 12),
              const Text(
                'الرسائل',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'تابع رسائلك مع مزودي الخدمة وفرق المنصة في مساحة أوضح وأكثر هدوءًا، مع إبراز الرسائل الجديدة والمفضلة والعملاء.',
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
                  _HeroTagChip(label: 'رسائل مباشرة'),
                  _HeroTagChip(label: 'فرق المنصة'),
                  _HeroTagChip(label: 'مرفقات آمنة'),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroStatChip(label: 'إجمالي المحادثات', value: '${_visibleThreads.length}'),
                  _HeroStatChip(label: 'غير المقروء', value: '$_totalUnreadMessages'),
                  _HeroStatChip(label: 'المفضلة', value: '$_favoriteThreadsCount'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool isDark, int visibleCount) {
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'قائمة الرسائل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A3347) : const Color(0xFFF4F8FB),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$visibleCount نتيجة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF52637A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSearchField(isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChip('الكل'),
                const SizedBox(width: 8),
                _buildFilterChip('غير مقروءة'),
                const SizedBox(width: 8),
                _buildFilterChip('مفضلة'),
                if (_isProviderAccount) ...[
                  const SizedBox(width: 8),
                  _buildFilterChip('عملاء'),
                ],
                const SizedBox(width: 8),
                _buildFilterChip('الأحدث'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => searchQuery = value.trim()),
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        hintText: 'ابحث في الرسائل...',
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF98A2B3),
        ),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => searchQuery = '');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: true,
        fillColor: isDark ? const Color(0xFF102231) : const Color(0xFFFCFCFD),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF22577A), width: 1.4),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark, List<ChatThread> sortedChats) {
    if (_isLoading) {
      return RefreshIndicator(
        onRefresh: _fetchThreads,
        color: const Color(0xFF22577A),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
          itemCount: 5,
          itemBuilder: (_, __) => _buildLoadingCard(isDark),
        ),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _fetchThreads,
        color: const Color(0xFF22577A),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
          children: [_buildErrorState(isDark)],
        ),
      );
    }

    if (sortedChats.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchThreads,
        color: const Color(0xFF22577A),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
          children: [_buildEmptyState(isDark)],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchThreads,
      color: const Color(0xFF22577A),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
        itemCount: sortedChats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _buildEntrance(
            index + 2,
            _buildChatTile(sortedChats[index], isDark),
          );
        },
      ),
    );
  }

  Widget _buildLoadingCard(bool isDark) {
    final base = isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94);
    final line = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EEF3);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: 150, color: line),
                const SizedBox(height: 10),
                Container(height: 10, width: double.infinity, color: line),
                const SizedBox(height: 6),
                Container(height: 10, width: 180, color: line),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(height: 22, width: 70, color: line),
                    const SizedBox(width: 8),
                    Container(height: 22, width: 56, color: line),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Container(
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
            _errorMessage ?? 'فشل تحميل المحادثات',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF52637A),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchThreads,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22577A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
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
          Icon(Icons.chat_bubble_outline_rounded,
              size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            'لا توجد رسائل حالياً',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _emptyMessage(),
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
    );
  }

  Widget _buildChatTile(ChatThread thread, bool isDark) {
    final kind = _threadKind(thread);
    final roleLabel = _threadRoleLabel(kind);
    final previewTone = _threadPreviewTone(thread, kind);
    final previewLabel = _threadPreviewLabel(previewTone, kind);
    final isUnread = thread.unreadCount > 0;
    final isFavorite = thread.isFavorite;
    final displayName = thread.peerDisplayName;
    final subtitle = _threadSubtitle(thread, kind);
    final imageUrl = ApiClient.buildMediaUrl(thread.peerProfileImage);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openThread(thread),
        onLongPress: () => _showChatOptions(thread),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnread
                ? const Color(0xFFF7FBFF)
                : isDark
                    ? const Color(0xFF132637)
                    : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isUnread
                  ? const Color(0xFFB4D5E8)
                  : isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE4EBF1),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C223D).withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: imageUrl == null
                          ? _avatarGradient(kind)
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: imageUrl == null
                          ? Center(
                              child: Text(
                                displayName.isNotEmpty ? displayName[0] : 'م',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) {
                                return Container(
                                  color: const Color(0xFFE4EBF1),
                                  alignment: Alignment.center,
                                  child: Text(
                                    displayName.isNotEmpty ? displayName[0] : 'م',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF22577A),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  if (thread.peerExcellenceBadges.isNotEmpty)
                    Positioned(
                      top: -6,
                      left: -4,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 92),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          thread.peerExcellenceBadges.first.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontSize: 8.8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (isUnread)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E7490),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 14,
                                        fontWeight:
                                            isUnread ? FontWeight.w900 : FontWeight.w800,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isFavorite)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 16,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                ],
                              ),
                              if (thread.peerExcellenceBadges.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ExcellenceBadgesWrap(
                                  badges: thread.peerExcellenceBadges,
                                  compact: true,
                                ),
                              ],
                              if (roleLabel.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _TinyChip(
                                  label: roleLabel,
                                  background: _kindBackground(kind),
                                  foreground: _kindForeground(kind),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTime(thread.lastMessageAt),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? const Color(0xFF9CB0C4)
                                    : const Color(0xFF667085),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _showChatOptions(thread),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF102231)
                                      : const Color(0xFFF4F8FB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.more_horiz_rounded,
                                  color: isDark
                                      ? const Color(0xFFB8C7D9)
                                      : const Color(0xFF52637A),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.3,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF9CB0C4)
                            : const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (previewLabel != null) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _TinyChip(
                            label: previewLabel.text,
                            background: previewLabel.background,
                            foreground: previewLabel.foreground,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      _threadPreviewText(thread.lastMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.2,
                        height: 1.6,
                        fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.92)
                            : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (thread.unreadCount > 0)
                          _TinyChip(
                            label: '${thread.unreadCount} جديد',
                            background: const Color(0xFFE0F2FE),
                            foreground: const Color(0xFF0369A1),
                          ),
                        if (thread.isFavorite)
                          _TinyChip(
                            label: (thread.favoriteLabel ?? '').trim().isNotEmpty
                                ? thread.favoriteLabel!.trim()
                                : 'مفضلة',
                            background: const Color(0xFFFFF4CC),
                            foreground: const Color(0xFF9A6700),
                          ),
                        if ((thread.clientLabel ?? '').trim().isNotEmpty)
                          _TinyChip(
                            label: thread.clientLabel!.trim(),
                            background: const Color(0xFFF4EBFF),
                            foreground: const Color(0xFF6D28D9),
                          ),
                        if (thread.peerLocationDisplay.trim().isNotEmpty)
                          _TinyChip(
                            label: thread.peerLocationDisplay.trim(),
                            background: const Color(0xFFF4F8FB),
                            foreground: const Color(0xFF52637A),
                          ),
                        _TinyChip(
                          label: 'فتح الرسائل',
                          background: isDark ? const Color(0xFF102231) : const Color(0xFFF4F8FB),
                          foreground: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF52637A),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _avatarGradient(_ThreadKind kind) {
    switch (kind) {
      case _ThreadKind.team:
        return const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case _ThreadKind.provider:
        return const LinearGradient(
          colors: [Color(0xFF0369A1), Color(0xFF38BDF8)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case _ThreadKind.client:
        return const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2DD4BF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case _ThreadKind.member:
        return const LinearGradient(
          colors: [Color(0xFF475467), Color(0xFF98A2B3)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
    }
  }

  Color _kindBackground(_ThreadKind kind) {
    switch (kind) {
      case _ThreadKind.team:
        return const Color(0xFFF4EBFF);
      case _ThreadKind.provider:
        return const Color(0xFFE0F2FE);
      case _ThreadKind.client:
        return const Color(0xFFE8FFF8);
      case _ThreadKind.member:
        return const Color(0xFFF4F8FB);
    }
  }

  Color _kindForeground(_ThreadKind kind) {
    switch (kind) {
      case _ThreadKind.team:
        return const Color(0xFF6D28D9);
      case _ThreadKind.provider:
        return const Color(0xFF0369A1);
      case _ThreadKind.client:
        return const Color(0xFF0F766E);
      case _ThreadKind.member:
        return const Color(0xFF52637A);
    }
  }

  Widget _buildFilterChip(String label) {
    final isSelected = selectedFilter == label;
    final count = _filterCount(label);

    return InkWell(
      onTap: () => setState(() => selectedFilter = label),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF22577A) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? const Color(0xFF22577A) : const Color(0xFFD0D5DD),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : const Color(0xFF22577A),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.16) : const Color(0xFFF4F8FB),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : const Color(0xFF52637A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.07 * index).clamp(0.0, 0.82).toDouble();
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

enum _ThreadKind { team, provider, client, member }

enum _PreviewTone { team, service, defaultTone }

class _PreviewLabel {
  final String text;
  final Color background;
  final Color foreground;

  const _PreviewLabel(this.text, this.background, this.foreground);
}

class _HeroTagChip extends StatelessWidget {
  final String label;

  const _HeroTagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  final String label;
  final String value;

  const _HeroStatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.72),
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
}

class _TinyChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _TinyChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
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
          fontSize: 9.8,
          fontWeight: FontWeight.w900,
          color: foreground,
        ),
      ),
    );
  }
}
