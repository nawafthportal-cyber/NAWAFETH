import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nawafeth/services/account_mode_service.dart';

import '../../models/service_request_model.dart';
import '../../services/marketplace_service.dart';
import '../../widgets/bottom_nav.dart';
import '../client_orders_screen.dart';
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

class _ProviderOrdersScreenState extends State<ProviderOrdersScreen> {
  static const Color _mainColor = Colors.deepPurple;

  final TextEditingController _searchController = TextEditingController();
  String? _selectedStatus;
  _ProviderOrdersTab _activeTab = _ProviderOrdersTab.assigned;

  List<ServiceRequest> _assignedOrders = [];
  List<ServiceRequest> _competitiveOrders = [];
  List<ServiceRequest> _urgentOrders = [];

  bool _loading = true;
  String? _error;

  bool _accountChecked = false;
  bool _isProviderAccount = false;

  @override
  void initState() {
    super.initState();
    _ensureProviderAccount();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
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
    _searchController.dispose();
    super.dispose();
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
          (o.city ?? '').toLowerCase().contains(query);
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
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withAlpha(26),
        side: BorderSide(color: color.withAlpha(90)),
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
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withAlpha(20),
        side: BorderSide(color: color.withAlpha(100)),
        onSelected: (_) => _onTabChanged(tab),
      ),
    );
  }

  Widget _orderCard(ServiceRequest order) {
    final statusColor = _statusColor(order.statusGroup);
    final showAvailableTag =
        _activeTab != _ProviderOrdersTab.assigned && order.provider == null;

    return InkWell(
      onTap: () => _openDetails(order),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${order.displayId}  ${order.clientName ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (order.requestType != 'normal')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: order.requestType == 'urgent'
                                ? Colors.red.withAlpha(25)
                                : Colors.blue.withAlpha(25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            order.requestTypeLabel,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: order.requestType == 'urgent'
                                  ? Colors.red
                                  : Colors.blue,
                            ),
                          ),
                        ),
                      if (showAvailableTag) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.withAlpha(22),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Colors.teal.withAlpha(60)),
                          ),
                          child: const Text(
                            'متاح',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(28),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: statusColor.withAlpha(80)),
                  ),
                  child: Text(
                    order.statusLabel.isNotEmpty
                        ? order.statusLabel
                        : order.statusGroup,
                    style: TextStyle(
                      color: statusColor,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              order.title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            if ((order.city ?? '').trim().isNotEmpty) ...[
              Text(
                'المدينة: ${order.city}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              _formatDate(order.createdAt),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final filtered = _filteredOrders();

    return Column(
      children: [
        TextField(
          controller: _searchController,
          style: const TextStyle(fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'بحث',
            hintStyle: const TextStyle(fontFamily: 'Cairo'),
            prefixIcon: const Icon(Icons.search, color: _mainColor),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
                color: Colors.blue.shade700,
              ),
              _tabChip(
                label: 'العاجلة المتاحة',
                count: _urgentOrders.length,
                tab: _ProviderOrdersTab.urgent,
                color: Colors.red.shade700,
              ),
            ],
          ),
        ),
        if (_activeTab == _ProviderOrdersTab.assigned) ...[
          const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadOrders,
                            child: const Text(
                              'إعادة المحاولة',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد طلبات',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.black54,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadOrders,
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _orderCard(filtered[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_accountChecked) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isProviderAccount) {
      return widget.embedded
          ? const SizedBox.shrink()
          : const Scaffold(body: SizedBox.shrink());
    }

    return widget.embedded
        ? _buildBody()
        : Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: Colors.grey[100],
              appBar: AppBar(
                backgroundColor: _mainColor,
                title: const Text(
                  'إدارة الطلبات',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
                ),
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildBody(),
              ),
            ),
          );
  }
}
