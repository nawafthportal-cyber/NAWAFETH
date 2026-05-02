import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/unread_badge_service.dart';

import '../../constants/request_status_filters.dart';
import '../../models/service_request_model.dart';
import '../../services/marketplace_service.dart';
import '../../constants/app_theme.dart';
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

class _ProviderHeroPill extends StatelessWidget {
  final String label;

  const _ProviderHeroPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ProviderHeroPanelPoint extends StatelessWidget {
  final String label;

  const _ProviderHeroPanelPoint({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.75,
              color: Colors.white.withValues(alpha: 0.80),
            ),
          ),
        ),
      ],
    );
  }
}

class ProviderOrdersScreen extends StatefulWidget {
  final bool embedded;
  final String? initialTab;

  const ProviderOrdersScreen({
    super.key,
    this.embedded = false,
    this.initialTab,
  });

  @override
  State<ProviderOrdersScreen> createState() => _ProviderOrdersScreenState();
}

class _ProviderOrdersScreenState extends State<ProviderOrdersScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = AppColors.teal;
  static const Color _competitiveColor = AppColors.info;
  static const Color _urgentColor = AppColors.error;
  static const Color _inkColor = AppTextStyles.textPrimary;

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

  _ProviderOrdersTab _tabFromInitialValue(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'urgent':
        return _ProviderOrdersTab.urgent;
      case 'competitive':
        return _ProviderOrdersTab.competitive;
      case 'assigned':
      default:
        return _ProviderOrdersTab.assigned;
    }
  }

  @override
  void initState() {
    super.initState();
    _activeTab = _tabFromInitialValue(widget.initialTab);
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
      final statusGroup =
          RequestStatusFilters.apiValueForLabel(_selectedStatus);

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
        _error = 'تعذر تحميل الطلبات';
        _loading = false;
      });
    }
  }

  Color _statusColor(String statusGroup) {
    switch (statusGroup) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.warning;
      case 'new':
        return AppColors.warning;
      default:
        return AppColors.grey400;
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

  bool get _isCompactLayout => MediaQuery.sizeOf(context).width < 390;

  bool get _isVeryCompactLayout => MediaQuery.sizeOf(context).width < 360;

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

  String _orderClientText(ServiceRequest order) {
    final client = order.clientName?.trim();
    if (client != null && client.isNotEmpty) return client;
    return 'غير محدد';
  }

  String _orderCityText(ServiceRequest order) {
    final city = order.locationDisplay.trim();
    if (city.isNotEmpty) return city;
    final fallback = order.city?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return 'غير محدد';
  }

  String _orderScheduleLabel(ServiceRequest order) {
    if ((order.quoteDeadline ?? '').trim().isNotEmpty) {
      return 'آخر موعد';
    }
    if (order.expectedDeliveryAt != null) {
      return 'موعد التسليم';
    }
    return 'تاريخ الإنشاء';
  }

  String _orderScheduleValue(ServiceRequest order) {
    final quoteDeadline = order.quoteDeadline?.trim();
    if (quoteDeadline != null && quoteDeadline.isNotEmpty) {
      return quoteDeadline;
    }
    if (order.expectedDeliveryAt != null) {
      return _formatDate(order.expectedDeliveryAt!);
    }
    return _formatDate(order.createdAt);
  }

  String _orderAmountText(ServiceRequest order) {
    final rawAmount = [
      order.actualServiceAmount,
      order.estimatedServiceAmount,
      order.receivedAmount,
      order.remainingAmount,
    ].firstWhere(
      (value) => value != null && value.trim().isNotEmpty,
      orElse: () => null,
    );
    if (rawAmount == null) return 'غير محدد';

    final parsedAmount = double.tryParse(rawAmount);
    if (parsedAmount == null) return rawAmount;
    return '${NumberFormat.decimalPattern('ar').format(parsedAmount)} ر.س';
  }

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
    final shouldResetAssignedFilter =
        tab != _ProviderOrdersTab.assigned && _selectedStatus != null;
    setState(() {
      _activeTab = tab;
      if (shouldResetAssignedFilter) {
        _selectedStatus = null;
      }
    });
    if (shouldResetAssignedFilter) {
      _loadOrders();
    }
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
    final compact = _isCompactLayout;
    final isAllFilter = label == RequestStatusFilters.allLabel;
    final isSelected =
        isAllFilter ? _selectedStatus == null : _selectedStatus == label;
    final statusGroup = RequestStatusFilters.apiValueForLabel(label);
    final color = isAllFilter ? _mainColor : _statusColor(statusGroup ?? '');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding:
            EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 0),
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: compact ? 10.5 : 11,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withAlpha(24),
        side: BorderSide(color: color.withAlpha(80)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (_) => _onStatusChanged(
          isAllFilter ? null : (isSelected ? null : label),
        ),
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required int count,
    required _ProviderOrdersTab tab,
    required Color color,
  }) {
    final compact = _isCompactLayout;
    final isSelected = _activeTab == tab;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding:
            EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 0),
        label: Text(
          '$label ($count)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: compact ? 10.5 : 11,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withAlpha(18),
        side: BorderSide(color: color.withAlpha(90)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (_) => _onTabChanged(tab),
      ),
    );
  }

  Widget _orderCard(ServiceRequest order, bool isDark) {
    final compact = _isCompactLayout;
    final veryCompact = _isVeryCompactLayout;
    final statusColor = _statusColor(order.statusGroup);
    final showAvailableTag =
        _activeTab != _ProviderOrdersTab.assigned && order.provider == null;
    final requestTypeColor = order.requestType == 'urgent'
        ? _urgentColor
        : order.requestType == 'competitive'
            ? _competitiveColor
            : _mainColor;
    final clientText = _orderClientText(order);
    final cityText = _orderCityText(order);
    final scheduleLabel = _orderScheduleLabel(order);
    final scheduleValue = _orderScheduleValue(order);
    final amountText = _orderAmountText(order);

    return InkWell(
      onTap: () => _openDetails(order),
      borderRadius: BorderRadius.circular(compact ? 18 : 20),
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? 10 : 12),
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF102928) : Colors.white,
          borderRadius: BorderRadius.circular(compact ? 18 : 20),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: _activeTabColor().withAlpha(18),
              blurRadius: compact ? 12 : 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
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
                      Text(
                        order.displayId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 12.5 : 13.5,
                          color: isDark ? Colors.white : _inkColor,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      Wrap(
                        spacing: compact ? 4 : 6,
                        runSpacing: compact ? 4 : 6,
                        children: [
                          if (order.requestType != 'normal')
                            _miniChip(
                              label: order.requestTypeLabel,
                              color: requestTypeColor,
                            ),
                          if (showAvailableTag)
                            _miniChip(label: 'متاح', color: _mainColor),
                        ],
                      ),
                      if ((order.clientName ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          order.clientName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: compact ? 10.2 : 10.8,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                _miniChip(
                  label: order.statusLabel.isNotEmpty
                      ? order.statusLabel
                      : order.statusGroup,
                  color: statusColor,
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),
            Text(
              order.title,
              maxLines: veryCompact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: compact ? 10.8 : 11.4,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            if ((order.categoryName ?? '').trim().isNotEmpty ||
                (order.subcategoryName ?? '').trim().isNotEmpty) ...[
              SizedBox(height: compact ? 10 : 12),
              Wrap(
                spacing: compact ? 6 : 8,
                runSpacing: compact ? 6 : 8,
                children: [
                  if ((order.categoryName ?? '').trim().isNotEmpty)
                    _miniChip(label: order.categoryName!.trim(), color: _mainColor),
                  if ((order.subcategoryName ?? '').trim().isNotEmpty)
                    _miniChip(
                      label: order.subcategoryName!.trim(),
                      color: const Color(0xFF0F766E),
                    ),
                ],
              ),
            ],
            SizedBox(height: compact ? 10 : 12),
            Container(
              padding: EdgeInsets.all(compact ? 10 : 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: veryCompact
                  ? Column(
                      children: [
                        _buildOrderInfoTile(
                          label: 'العميل',
                          value: clientText,
                          isDark: isDark,
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        _buildOrderInfoTile(
                          label: 'المدينة',
                          value: cityText,
                          isDark: isDark,
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        _buildOrderInfoTile(
                          label: scheduleLabel,
                          value: scheduleValue,
                          isDark: isDark,
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        _buildOrderInfoTile(
                          label: 'القيمة',
                          value: amountText,
                          isDark: isDark,
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildOrderInfoTile(
                                label: 'العميل',
                                value: clientText,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildOrderInfoTile(
                                label: 'المدينة',
                                value: cityText,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildOrderInfoTile(
                                label: scheduleLabel,
                                value: scheduleValue,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildOrderInfoTile(
                                label: 'القيمة',
                                value: amountText,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            SizedBox(height: compact ? 10 : 12),
            Container(
              padding: EdgeInsets.only(top: compact ? 10 : 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDate(order.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: compact ? 9.8 : 10.2,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: compact ? 8 : 9,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _activeTabColor(),
                          _activeTabColor().withValues(alpha: 0.82),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: _activeTabColor().withAlpha(32),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        SizedBox(width: compact ? 5 : 6),
                        const Text(
                          'فتح الطلب',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.4,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
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

  Widget _buildBody(bool isDark) {
    final compact = _isCompactLayout;
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
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 10 : (compact ? 12 : 14),
          compact ? 10 : 12,
          widget.embedded ? 10 : (compact ? 12 : 14),
          compact ? 12 : 14,
        ),
        child: Column(
          children: [
            _buildEntrance(0, _buildHero(isDark)),
            SizedBox(height: compact ? 10 : 12),
            _buildEntrance(1, _buildControlPanel(isDark)),
            SizedBox(height: compact ? 10 : 12),
            Expanded(child: _buildEntrance(2, _buildOrdersSurface(isDark, filtered))),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel(bool isDark) {
    final compact = _isCompactLayout;
    final awaitingAcceptanceCount =
        _assignedOrders.where((order) => order.statusGroup == 'new').length;
    final awaitingClientCount =
        _assignedOrders.where((order) => order.status == 'awaiting_client').length;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF102928) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(compact ? 20 : 22),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: _mainColor.withAlpha(12),
            blurRadius: compact ? 12 : 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 12 : 13),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(compact ? 16 : 18),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'لوحة التحكم',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: compact ? 10.2 : 10.7,
                    fontWeight: FontWeight.w800,
                    color: _activeTabColor(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'تصفية ومتابعة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: compact ? 13.2 : 14,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : _inkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'بانتظار القبول: $awaitingAcceptanceCount • بانتظار اعتماد العميل: $awaitingClientCount',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: compact ? 10 : 10.4,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            'البحث الذكي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 10.1 : 10.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
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
                fontSize: compact ? 10.2 : 10.8,
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
              contentPadding: EdgeInsets.symmetric(
                vertical: compact ? 12 : 13,
                horizontal: compact ? 12 : 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(compact ? 15 : 16),
                borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(compact ? 15 : 16),
                borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(compact ? 15 : 16),
                ),
                borderSide: const BorderSide(color: _mainColor),
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tabChip(
                  label: 'المسندة',
                  count: _assignedOrders.length,
                  tab: _ProviderOrdersTab.assigned,
                  color: _mainColor,
                ),
                _tabChip(
                  label: 'الأسعار',
                  count: _competitiveOrders.length,
                  tab: _ProviderOrdersTab.competitive,
                  color: _competitiveColor,
                ),
                _tabChip(
                  label: 'العاجلة',
                  count: _urgentOrders.length,
                  tab: _ProviderOrdersTab.urgent,
                  color: _urgentColor,
                ),
              ],
            ),
          ),
          if (_activeTab == _ProviderOrdersTab.assigned) ...[
            SizedBox(height: compact ? 10 : 12),
            Text(
              'فلتر الحالة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: compact ? 10.1 : 10.5,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statusFilterChip(RequestStatusFilters.allLabel),
                  _statusFilterChip('جديد'),
                  _statusFilterChip('تحت التنفيذ'),
                  _statusFilterChip('مكتمل'),
                  _statusFilterChip('ملغي'),
                ],
              ),
            ),
            SizedBox(height: compact ? 10 : 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 10 : 11),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(compact ? 14 : 15),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendRow(
                    label: 'طلب جديد يحتاج مراجعة أو قبول',
                    color: AppColors.warning,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 7),
                  _buildLegendRow(
                    label: 'طلب قيد التنفيذ أو المتابعة',
                    color: AppColors.warning,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 7),
                  _buildLegendRow(
                    label: 'طلب مكتمل وتم إغلاقه',
                    color: AppColors.success,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 7),
                  _buildLegendRow(
                    label: 'طلب ملغي أو منتهي',
                    color: AppColors.error,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 10 : 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 11 : 12),
              decoration: BoxDecoration(
                color: _activeTabColor().withAlpha(isDark ? 20 : 12),
                borderRadius: BorderRadius.circular(compact ? 15 : 16),
                border: Border.all(color: _activeTabColor().withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إيقاع تشغيل أنظف',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: compact ? 10.5 : 11,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : _inkColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'استخدم التبويبات العلوية للتبديل بين نوع الطلبات، ثم ضيّق النتائج بالحالة والبحث من هنا بسرعة.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: compact ? 9.9 : 10.2,
                      fontWeight: FontWeight.w700,
                      height: 1.7,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: compact ? 10 : 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'الترتيب: الأحدث',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: compact ? 9.7 : 10,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersSurface(bool isDark, List<ServiceRequest> filtered) {
    final compact = _isCompactLayout;
    final activeViewLabel = switch (_activeTab) {
      _ProviderOrdersTab.assigned => 'المسندة لي',
      _ProviderOrdersTab.competitive => 'الفرص التنافسية',
      _ProviderOrdersTab.urgent => 'الطلبات العاجلة',
    };
    final activeViewBadge = switch (_activeTab) {
      _ProviderOrdersTab.assigned => 'مباشر',
      _ProviderOrdersTab.competitive => 'منافسة',
      _ProviderOrdersTab.urgent => 'عاجل',
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF102928) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(compact ? 20 : 22),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: _activeTabColor().withAlpha(12),
            blurRadius: compact ? 12 : 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 12 : 13),
            decoration: BoxDecoration(
              color: _activeTabColor().withAlpha(isDark ? 20 : 12),
              borderRadius: BorderRadius.circular(compact ? 16 : 18),
              border: Border.all(color: _activeTabColor().withAlpha(40)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              activeViewLabel,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: compact ? 12.2 : 12.8,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : _inkColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _activeTabColor().withAlpha(isDark ? 38 : 24),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              activeViewBadge,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: compact ? 9.5 : 9.9,
                                fontWeight: FontWeight.w900,
                                color: _activeTabColor(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filtered.length} طلب ظاهر',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: compact ? 10 : 10.3,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(18) : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    'عرض منظم حسب التبويب الحالي',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: compact ? 9.6 : 10,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
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
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : _inkColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${filtered.length} نتيجة بعد البحث والتصفية',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: compact ? 9.8 : 10.2,
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
          SizedBox(height: compact ? 10 : 12),
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
    final compact = _isCompactLayout;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
        margin: EdgeInsets.only(bottom: compact ? 10 : 12),
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F8),
          borderRadius: BorderRadius.circular(compact ? 18 : 20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 12, width: 110, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 8),
            Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 6),
            Container(height: 10, width: 150, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
            SizedBox(height: compact ? 10 : 12),
            Row(
              children: List.generate(
                2,
                (_) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Container(height: 24, width: 64, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999))),
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
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _inkColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أعد المحاولة لتحديث القائمة.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.2,
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
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _inkColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'حدّث القائمة أو بدّل التبويب.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip({required String label, required Color color}) {
    final compact = _isCompactLayout;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: compact ? 9.6 : 10.2,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLegendRow({
    required String label,
    required Color color,
    required bool isDark,
  }) {
    final compact = _isCompactLayout;
    return Row(
      children: [
        Container(
          width: compact ? 8 : 9,
          height: compact ? 8 : 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: compact ? 7 : 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 9.6 : 9.9,
              fontWeight: FontWeight.w700,
              height: 1.6,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderInfoTile({
    required String label,
    required String value,
    required bool isDark,
  }) {
    final compact = _isCompactLayout;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 11),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 9.2 : 9.6,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 10.1 : 10.6,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _inkColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(bool isDark) {
    final compact = _isCompactLayout;
    final awaitingAcceptanceCount =
        _assignedOrders.where((order) => order.statusGroup == 'new').length;
    final awaitingClientCount =
        _assignedOrders.where((order) => order.status == 'awaiting_client').length;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B1237), Color(0xFF44258A), Color(0xFF1483A0)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x381D113A),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Text(
              'لوحة إدارة الطلبات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          const Text(
            'إدارة الطلبات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'واجهة واحدة لمتابعة الطلبات المسندة لك، واغتنام الفرص التنافسية، والتعامل السريع مع الطلبات العاجلة بتوزيع أكثر هدوءًا ووضوحًا.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              height: 1.8,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _ProviderHeroPill(label: 'متابعة لحظية'),
              _ProviderHeroPill(label: 'بحث وفرز سريع'),
              _ProviderHeroPill(label: 'عرض احترافي متعدد الحالات'),
            ],
          ),
          SizedBox(height: compact ? 14 : 16),
          Row(
            children: [
              Expanded(
                child: _buildHeroStatCard(
                  label: 'الطلبات المسندة',
                  value: _assignedOrders.length.toString(),
                  note: 'الأساس اليومي لإدارة التنفيذ.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeroStatCard(
                  label: 'الفرص التنافسية',
                  value: _competitiveOrders.length.toString(),
                  note: 'طلبات عروض الأسعار المفتوحة الآن.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeroStatCard(
                  label: 'العاجلة',
                  value: _urgentOrders.length.toString(),
                  note: 'طلبات تحتاج استجابة أسرع.',
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 14),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 14 : 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مركز التشغيل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: compact ? 10.5 : 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'لوحة أكثر هدوءًا ووضوحًا',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'بانتظار القبول: $awaitingAcceptanceCount • بانتظار اعتماد العميل: $awaitingClientCount',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: compact ? 10.4 : 10.8,
                    fontWeight: FontWeight.w700,
                    height: 1.8,
                    color: Colors.white.withValues(alpha: 0.80),
                  ),
                ),
                SizedBox(height: compact ? 10 : 12),
                const _ProviderHeroPanelPoint(
                  label: 'انتقال سريع بين الطلبات المسندة والتنافسية والعاجلة.',
                ),
                const SizedBox(height: 8),
                const _ProviderHeroPanelPoint(
                  label: 'ملخص واضح للحالة والمدينة والقيمة وموعد التسليم.',
                ),
                const SizedBox(height: 8),
                const _ProviderHeroPanelPoint(
                  label: 'واجهة أكثر اتزانًا على الجوال والديسكتوب.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatCard({
    required String label,
    required String value,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
        ],
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
