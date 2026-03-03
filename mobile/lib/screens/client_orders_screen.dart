import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/service_request_model.dart';
import '../services/account_mode_service.dart';
import '../services/marketplace_service.dart';
import '../widgets/bottom_nav.dart';
import 'client_order_details_screen.dart';
import 'provider_dashboard/provider_orders_screen.dart';

class ClientOrdersScreen extends StatefulWidget {
  final bool embedded;

  const ClientOrdersScreen({super.key, this.embedded = false});

  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
  static const Color _mainColor = Colors.deepPurple;

  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'الكل';

  List<ServiceRequest> _orders = [];
  bool _loading = true;
  String? _error;
  bool _accountChecked = false;
  bool _isProviderMode = false;

  @override
  void initState() {
    super.initState();
    _ensureClientAccount();
    _searchController.addListener(() {
      if (mounted) setState(() {});
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
    _searchController.dispose();
    super.dispose();
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
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _mainColor.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _mainColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? _mainColor : Colors.black54,
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
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
        appBar: AppBar(
          backgroundColor: _mainColor,
          title: const Text(
            'طلباتي',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
        body: _buildBody(isDark: isDark),
      ),
    );
  }

  Widget _buildBody({required bool isDark}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            children: [
              // حقل البحث
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'بحث',
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
                        icon: const Icon(Icons.close, color: Colors.grey),
                        tooltip: 'مسح',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // فلاتر الحالة
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
        ),
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
                            child: const Text('إعادة المحاولة',
                                style: TextStyle(fontFamily: 'Cairo')),
                          ),
                        ],
                      ),
                    )
                  : _orders.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد طلبات',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadOrders,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _orders.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              final order = _orders[index];
                              return _orderCard(order: order, isDark: isDark);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _orderCard({required ServiceRequest order, required bool isDark}) {
    final statusColor = _statusColor(order.statusGroup);

    return InkWell(
      onTap: () => _openDetails(order),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        order.displayId,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // نوع الطلب
                      if (order.requestType != 'normal')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: order.requestType == 'urgent'
                                ? Colors.red.withAlpha(25)
                                : Colors.blue.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    order.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (order.providerName != null &&
                      order.providerName!.isNotEmpty)
                    Text(
                      order.providerName!,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(order.createdAt),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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
      ),
    );
  }
}
