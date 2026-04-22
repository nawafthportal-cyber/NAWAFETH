import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../constants/app_theme.dart';
import '../models/service_request_model.dart';
import '../services/account_mode_service.dart';
import '../services/marketplace_service.dart';
import '../services/unread_badge_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/platform_top_bar.dart';
import 'client_order_details_screen.dart';
import 'my_chats_screen.dart';
import 'notifications_screen.dart';
import 'provider_dashboard/provider_orders_screen.dart';

class ClientOrdersScreen extends StatefulWidget {
  final bool embedded;

  const ClientOrdersScreen({super.key, this.embedded = false});

  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = AppColors.primary;
  static const Color _accentColor = Color(0xFF22577A);

  final TextEditingController _searchController = TextEditingController();
  late final AnimationController _entranceController;
  String _selectedFilter = 'الكل';

  List<ServiceRequest> _orders = [];
  bool _loading = true;
  String? _error;
  bool _accountChecked = false;
  bool _isProviderMode = false;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  ValueListenable<UnreadBadges>? _badgeHandle;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _ensureClientAccount();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  Future<void> _ensureClientAccount() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;

    setState(() {
      _isProviderMode = isProvider;
      _accountChecked = true;
    });

    if (_isProviderMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProviderOrdersScreen()),
        );
      });
      return;
    }

    _loadOrders();
  }

  @override
  void dispose() {
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    _entranceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeHandle?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  /// ─── تحميل الطلبات من API ───
  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // تحويل الفلتر العربي إلى قيمة API
      String? statusGroup;
      switch (_selectedFilter) {
        case 'جديد':
          statusGroup = 'new';
          break;
        case 'تحت التنفيذ':
          statusGroup = 'in_progress';
          break;
        case 'مكتمل':
          statusGroup = 'completed';
          break;
        case 'ملغي':
          statusGroup = 'cancelled';
          break;
      }

      final query = _searchController.text.trim();
      final orders = await MarketplaceService.getClientRequests(
        statusGroup: statusGroup,
        query: query.isNotEmpty ? query : null,
      );

      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الطلبات';
        _loading = false;
      });
    }
  }

  Color _statusColor(String statusGroup) {
    switch (statusGroup) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'new':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(date);
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _mainColor.withAlpha(22) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? _mainColor : AppColors.grey300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTextStyles.bodyMd,
            fontWeight: FontWeight.w600,
            color: selected ? _mainColor : AppTextStyles.textSecondary,
          ),
        ),
      ),
    );
  }

  void _onFilterChanged(String filter) {
    setState(() => _selectedFilter = filter);
    _loadOrders();
  }

  Future<void> _openDetails(ServiceRequest order) async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientOrderDetailsScreen(requestId: order.id),
      ),
    );

    if (!mounted) return;
    if (refreshed == true) _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_accountChecked) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: _mainColor),
          ),
        ),
      );
    }

    if (widget.embedded) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: _buildBody(isDark: isDark),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: PlatformTopBar(
          pageLabel: 'طلباتي',
          showBackButton: Navigator.of(context).canPop(),
          notificationCount: _notificationUnread,
          chatCount: _chatUnread,
          onNotificationsTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            );
            await UnreadBadgeService.refresh(force: true);
          },
          onChatsTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MyChatsScreen(),
              ),
            );
            await UnreadBadgeService.refresh(force: true);
          },
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
        body: _buildBody(isDark: isDark),
      ),
    );
  }

  Widget _buildBody({required bool isDark}) {
    final totalCount = _orders.length;
    final activeCount = _orders.where((o) =>
        o.statusGroup == 'new' || o.statusGroup == 'in_progress').length;
    final resultsCount = _orders.length;

    return Container(
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _buildEntrance(
              0,
              _buildHeroCard(
                isDark: isDark,
                totalCount: totalCount,
                activeCount: activeCount,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _buildEntrance(
              1,
              _buildControlPanel(
                isDark: isDark,
                resultsCount: resultsCount,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: _buildEntrance(2, _buildOrdersSurface(isDark: isDark)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderCard({required ServiceRequest order, required bool isDark}) {
    final statusColor = _statusColor(order.statusGroup);

    return InkWell(
      onTap: () => _openDetails(order),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132637) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
          boxShadow: isDark ? null : AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatDate(order.createdAt),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF667085),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withValues(alpha: 0.32)),
                  ),
                  child: Text(
                    order.statusLabel.isNotEmpty ? order.statusLabel : order.statusGroup,
                    style: TextStyle(
                      color: statusColor,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildOrderChip(
                  label: order.displayId,
                  background: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                if (order.requestType != 'normal')
                  _buildOrderChip(
                    label: order.requestTypeLabel,
                    background: order.requestType == 'urgent'
                        ? const Color(0xFFFFF1F1)
                        : const Color(0xFFEFF6FF),
                    color: order.requestType == 'urgent'
                        ? const Color(0xFFB42318)
                        : const Color(0xFF1D4ED8),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              order.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.h2,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppTextStyles.textPrimary,
              ),
            ),
            if (order.description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                order.description.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.bodySm,
                  height: 1.7,
                  fontWeight: FontWeight.w500,
                  color: isDark ? const Color(0xFFB8C7D9) : AppTextStyles.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (order.providerName != null && order.providerName!.isNotEmpty)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 15,
                          color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF667085),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            order.providerName!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF667085),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  'عرض التفاصيل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : _accentColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_left_rounded,
                  color: isDark ? Colors.white : _accentColor,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard({
    required bool isDark,
    required int totalCount,
    required int activeCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
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
            top: -36,
            left: -20,
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
            bottom: -58,
            right: -18,
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
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'لوحة الطلبات',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'تصفح طلباتك، راقب حالتها، وافتح التفاصيل بضغطة واحدة.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            height: 1.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _heroStat(
                      value: totalCount.toString(),
                      label: 'إجمالي الطلبات',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _heroStat(
                      value: activeCount.toString(),
                      label: 'طلبات نشطة',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel({required bool isDark, required int resultsCount}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0x220E5E85),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'قائمة الطلبات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'فلترة وبحث سريع للوصول إلى الطلب المطلوب.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark ? Colors.white10 : const Color(0xFFE4EBF1),
                  ),
                ),
                child: Text(
                  resultsCount.toString(),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : _accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF102231) : const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFDCE6ED),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF667085),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'بحث',
                      hintStyle: TextStyle(fontFamily: 'Cairo'),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontFamily: 'Cairo'),
                    onSubmitted: (_) => _loadOrders(),
                  ),
                ),
                if (_searchController.text.trim().isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _loadOrders();
                    },
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    tooltip: 'مسح',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'الكل',
                  selected: _selectedFilter == 'الكل',
                  onTap: () => _onFilterChanged('الكل'),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'جديد',
                  selected: _selectedFilter == 'جديد',
                  onTap: () => _onFilterChanged('جديد'),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'تحت التنفيذ',
                  selected: _selectedFilter == 'تحت التنفيذ',
                  onTap: () => _onFilterChanged('تحت التنفيذ'),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'مكتمل',
                  selected: _selectedFilter == 'مكتمل',
                  onTap: () => _onFilterChanged('مكتمل'),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'ملغي',
                  selected: _selectedFilter == 'ملغي',
                  onTap: () => _onFilterChanged('ملغي'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersSurface({required bool isDark}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0x220E5E85),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _loading
          ? _buildLoadingState()
          : _error != null
              ? _buildErrorState(isDark: isDark)
              : _orders.isEmpty
                  ? _buildEmptyState(isDark: isDark)
                  : RefreshIndicator(
                      onRefresh: _loadOrders,
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: _orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final order = _orders[index];
                          return _orderCard(order: order, isDark: isDark);
                        },
                      ),
                    ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 128,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE4EBF1)),
        ),
      ),
    );
  }

  Widget _buildErrorState({required bool isDark}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFB8C7D9) : const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loadOrders,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
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
    );
  }

  Widget _buildEmptyState({required bool isDark}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_late_outlined,
              size: 62,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
            const SizedBox(height: 14),
            Text(
              _searchController.text.trim().isNotEmpty
                  ? 'لا توجد نتائج مطابقة'
                  : 'لا توجد طلبات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchController.text.trim().isNotEmpty
                  ? 'جرّب تعديل عبارة البحث أو تغيير حالة الفلترة الحالية.'
                  : 'ستظهر هنا طلباتك الحالية والسابقة بمجرد إنشائها.',
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
    );
  }

  Widget _buildOrderChip({
    required String label,
    required Color background,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
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
