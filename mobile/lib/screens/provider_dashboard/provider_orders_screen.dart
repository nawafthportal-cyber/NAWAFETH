import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/unread_badge_service.dart';

import '../../models/service_request_model.dart';
import '../../services/marketplace_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/platform_top_bar.dart';
import '../client_orders_screen.dart';
import '../my_chats_screen.dart';
import '../notifications_screen.dart';
import 'provider_order_details_screen.dart';

enum _ProviderOrdersTab {
  assigned,
  competitive,
  urgent,
}

class ProviderOrdersScreen extends StatefulWidget {
  final bool embedded;

  const ProviderOrdersScreen({super.key, this.embedded = false});

  @override
  State<ProviderOrdersScreen> createState() => _ProviderOrdersScreenState();
}

class _ProviderOrdersScreenState extends State<ProviderOrdersScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = Color(0xFF0F766E);
  static const Color _competitiveColor = Color(0xFF2563EB);
  static const Color _urgentColor = Color(0xFFDC2626);
  static const Color _inkColor = Color(0xFF0F172A);

  final TextEditingController _searchController = TextEditingController();
  late final AnimationController _entranceController;
  String? _selectedStatus;
  _ProviderOrdersTab _activeTab = _ProviderOrdersTab.assigned;

  List<ServiceRequest> _assignedOrders = [];
  List<ServiceRequest> _competitiveOrders = [];
  List<ServiceRequest> _urgentOrders = [];

  bool _loading = true;
  String? _error;

  bool _accountChecked = false;
  bool _isProviderAccount = false;
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
    _ensureProviderAccount();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  Future<void> _ensureProviderAccount() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderAccount = isProvider;
      _accountChecked = true;
    });

    if (!_isProviderAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ClientOrdersScreen()),
        );
      });
    } else {
      _loadOrders();
    }
  }

  @override
  void dispose() {
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    _searchController.dispose();
    _entranceController.dispose();
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

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? statusGroup;
      switch (_selectedStatus) {
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

      final results = await Future.wait([
        MarketplaceService.getProviderRequests(statusGroup: statusGroup),
        MarketplaceService.getAvailableCompetitiveRequests(),
        MarketplaceService.getAvailableUrgentRequests(),
      ]);

      if (!mounted) return;
      setState(() {
        _assignedOrders = results[0];
        _competitiveOrders = results[1];
        _urgentOrders = results[2];
        _loading = false;
      });
    } catch (_) {
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

  Color _activeTabColor() {
    switch (_activeTab) {
      case _ProviderOrdersTab.assigned:
        return _mainColor;
      case _ProviderOrdersTab.competitive:
        return _competitiveColor;
      case _ProviderOrdersTab.urgent:
        return _urgentColor;
    }
  }

  String _surfaceTitle() {
    switch (_activeTab) {
      case _ProviderOrdersTab.assigned:
        return 'الطلبات المسندة إليك';
      case _ProviderOrdersTab.competitive:
        return 'طلبات عروض الأسعار المتاحة';
      case _ProviderOrdersTab.urgent:
        return 'الطلبات العاجلة المتاحة';
    }
  }

  String _formatDate(DateTime date) =>
      DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(date);

  List<ServiceRequest> _currentOrders() {
    switch (_activeTab) {
      case _ProviderOrdersTab.assigned:
        return _assignedOrders;
      case _ProviderOrdersTab.competitive:
        return _competitiveOrders;
      case _ProviderOrdersTab.urgent:
        return _urgentOrders;
    }
  }

  List<ServiceRequest> _filteredOrders() {
    final query = _searchController.text.trim().toLowerCase();
    final current = _currentOrders();
    if (query.isEmpty) return current;

    return current.where((o) {
      return o.displayId.toLowerCase().contains(query) ||
          o.title.toLowerCase().contains(query) ||
          (o.clientName ?? '').toLowerCase().contains(query) ||
          ('${o.locationDisplay} ${o.city ?? ''}').toLowerCase().contains(query);
    }).toList();
  }

  void _onStatusChanged(String? status) {
    setState(() => _selectedStatus = status);
    _loadOrders();
  }

  void _onTabChanged(_ProviderOrdersTab tab) {
    setState(() {
      _activeTab = tab;
      if (tab != _ProviderOrdersTab.assigned) {
        _selectedStatus = null;
      }
    });
  }

  Future<void> _openDetails(ServiceRequest order) async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderOrderDetailsScreen(requestId: order.id),
      ),
    );

    if (!mounted) return;
    if (refreshed == true) _loadOrders();
  }

  Widget _statusFilterChip(String label) {
    final isSelected = _selectedStatus == label;
    final arabicToStatus = {
      'جديد': 'new',
      'تحت التنفيذ': 'in_progress',
      'مكتمل': 'completed',
      'ملغي': 'cancelled',
    };
    final color = _statusColor(arabicToStatus[label] ?? '');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withAlpha(24),
        side: BorderSide(color: color.withAlpha(80)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onSelected: (_) => _onStatusChanged(isSelected ? null : label),
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required int count,
    required _ProviderOrdersTab tab,
    required Color color,
  }) {
    final isSelected = _activeTab == tab;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(
          '$label ($count)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withAlpha(18),
        side: BorderSide(color: color.withAlpha(90)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onSelected: (_) => _onTabChanged(tab),
      ),
    );
  }

  Widget _orderCard(ServiceRequest order, bool isDark) {
    final statusColor = _statusColor(order.statusGroup);
    final showAvailableTag =
        _activeTab != _ProviderOrdersTab.assigned && order.provider == null;
    final requestTypeColor = order.requestType == 'urgent'
        ? _urgentColor
        : order.requestType == 'competitive'
            ? _competitiveColor
            : _mainColor;

    return InkWell(
      onTap: () => _openDetails(order),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF102928) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: _activeTabColor().withAlpha(18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: requestTypeColor.withAlpha(22),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    order.requestType == 'urgent'
                        ? Icons.local_fire_department_rounded
                        : order.requestType == 'competitive'
                            ? Icons.request_quote_rounded
                            : Icons.assignment_outlined,
                    color: requestTypeColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.displayId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: isDark ? Colors.white : _inkColor,
                        ),
                      ),
                      if ((order.clientName ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          order.clientName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _miniChip(
                            label: order.statusLabel.isNotEmpty
                                ? order.statusLabel
                                : order.statusGroup,
                            color: statusColor,
                          ),
                          if (order.requestType != 'normal')
                            _miniChip(
                              label: order.requestTypeLabel,
                              color: requestTypeColor,
                            ),
                          if (showAvailableTag)
                            _miniChip(label: 'متاح', color: _mainColor),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                height: 1.7,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  _infoRow(
                    icon: Icons.place_outlined,
                    label: 'الموقع',
                    value: order.locationDisplay.trim().isNotEmpty
                        ? order.locationDisplay
                        : (order.city?.trim().isNotEmpty == true ? order.city! : 'غير محدد'),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    icon: Icons.schedule_rounded,
                    label: 'تاريخ الإنشاء',
                    value: _formatDate(order.createdAt),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final filtered = _filteredOrders();

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF081B1A), Color(0xFF0E2524), Color(0xFF14302E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFFEFFCFA), Color(0xFFF7FFFD), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.embedded ? 12 : 16, 12, widget.embedded ? 12 : 16, 16),
        child: Column(
          children: [
            _buildEntrance(0, _buildHeroCard(isDark)),
            const SizedBox(height: 12),
            _buildEntrance(1, _buildControlPanel(isDark)),
            const SizedBox(height: 12),
            Expanded(child: _buildEntrance(2, _buildOrdersSurface(isDark, filtered))),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF115E59), Color(0xFF0F766E), Color(0xFF14B8A6)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF115E59).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            left: -16,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -52,
            right: -18,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.embedded ? 'طلباتك كمزوّد' : 'إدارة الطلبات',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'تابع الطلبات المسندة، التنافسية، والعاجلة من مكان واحد مع وصول أسرع للحالات المتاحة.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroStat('المسندة', _assignedOrders.length.toString()),
                  _heroStat('التنافسية', _competitiveOrders.length.toString()),
                  _heroStat('العاجلة', _urgentOrders.length.toString()),
                  _heroStat('غير المقروءة', (_notificationUnread + _chatUnread).toString()),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.85),
            ),
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
        color: isDark ? const Color(0xFF102928) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: _mainColor.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: isDark ? Colors.white : _inkColor,
            ),
            decoration: InputDecoration(
              hintText: 'ابحث برقم الطلب أو العميل أو المدينة',
              hintStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
              ),
              prefixIcon: const Icon(Icons.search_rounded, color: _mainColor),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF6FBFA),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: _mainColor),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tabChip(
                  label: 'المسندة لي',
                  count: _assignedOrders.length,
                  tab: _ProviderOrdersTab.assigned,
                  color: _mainColor,
                ),
                _tabChip(
                  label: 'عروض الأسعار',
                  count: _competitiveOrders.length,
                  tab: _ProviderOrdersTab.competitive,
                  color: _competitiveColor,
                ),
                _tabChip(
                  label: 'العاجلة المتاحة',
                  count: _urgentOrders.length,
                  tab: _ProviderOrdersTab.urgent,
                  color: _urgentColor,
                ),
              ],
            ),
          ),
          if (_activeTab == _ProviderOrdersTab.assigned) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statusFilterChip('جديد'),
                  _statusFilterChip('تحت التنفيذ'),
                  _statusFilterChip('مكتمل'),
                  _statusFilterChip('ملغي'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrdersSurface(bool isDark, List<ServiceRequest> filtered) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF102928) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: _activeTabColor().withAlpha(12),
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
                      _surfaceTitle(),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : _inkColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${filtered.length} نتيجة بعد البحث والتصفية',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.8,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadOrders,
                icon: const Icon(Icons.refresh_rounded),
                color: _activeTabColor(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? _buildLoadingState()
                : _error != null
                    ? _buildErrorState(isDark)
                    : filtered.isEmpty
                        ? _buildEmptyState(isDark)
                        : RefreshIndicator(
                            color: _activeTabColor(),
                            onRefresh: _loadOrders,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _orderCard(filtered[i], isDark),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 14, width: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 10),
            Container(height: 12, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 8),
            Container(height: 12, width: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 14),
            Row(
              children: List.generate(
                2,
                (_) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Container(height: 28, width: 72, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 34, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _inkColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أعد المحاولة لتحميل الطلبات المتاحة وتحديث القوائم.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _loadOrders,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'إعادة المحاولة',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _activeTabColor(),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final icon = _activeTab == _ProviderOrdersTab.urgent
        ? Icons.local_fire_department_outlined
        : _activeTab == _ProviderOrdersTab.competitive
            ? Icons.request_quote_outlined
            : Icons.assignment_late_outlined;
    final message = _activeTab == _ProviderOrdersTab.assigned
        ? 'لا توجد طلبات مسندة لك حاليًا.'
        : _activeTab == _ProviderOrdersTab.competitive
            ? 'لا توجد طلبات عروض أسعار متاحة الآن.'
            : 'لا توجد طلبات عاجلة متاحة الآن.';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _activeTabColor().withAlpha(18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: _activeTabColor()),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _inkColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'جرّب تحديث القائمة أو تبديل التبويب أو تعديل البحث.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _mainColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white60 : const Color(0xFF64748B),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : _inkColor,
            ),
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_accountChecked) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator(color: _mainColor));
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _mainColor)),
      );
    }

    if (!_isProviderAccount) {
      return widget.embedded
          ? const SizedBox.shrink()
          : const Scaffold(body: SizedBox.shrink());
    }

    return widget.embedded
        ? _buildBody(isDark)
        : Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: isDark ? const Color(0xFF081B1A) : const Color(0xFFEFFCFA),
              appBar: PlatformTopBar(
                pageLabel: 'إدارة الطلبات',
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
              body: _buildBody(isDark),
            ),
          );
  }
}
