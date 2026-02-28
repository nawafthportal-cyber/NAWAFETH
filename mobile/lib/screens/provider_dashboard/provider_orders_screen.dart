import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nawafeth/services/account_mode_service.dart';

import '../../models/service_request_model.dart';
import '../../services/marketplace_service.dart';
import '../client_orders_screen.dart';
import 'provider_order_details_screen.dart';

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

  List<ServiceRequest> _orders = [];
  bool _loading = true;
  String? _error;

  bool _accountChecked = false;
  bool _isProviderAccount = false;

  @override
  void initState() {
    super.initState();
    _ensureProviderAccount();
    _searchController.addListener(() {
      if (mounted) setState(() {});
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

  /// ─── تحميل الطلبات من API ───
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

      final orders = await MarketplaceService.getProviderRequests(
        statusGroup: statusGroup,
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

  String _formatDate(DateTime date) =>
      DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(date);

  /// فلترة محلية بالبحث النصي (API لا تدعم search للمزوّد)
  List<ServiceRequest> _filteredOrders() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _orders;

    return _orders.where((o) {
      return o.displayId.toLowerCase().contains(query) ||
          o.title.toLowerCase().contains(query) ||
          (o.clientName ?? '').toLowerCase().contains(query);
    }).toList();
  }

  void _onStatusChanged(String? status) {
    setState(() => _selectedStatus = status);
    _loadOrders();
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

  Widget _filterChip(String label) {
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

  Widget _orderCard(ServiceRequest order) {
    final statusColor = _statusColor(order.statusGroup);
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
                color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
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
                      Text(
                        '${order.displayId}  ${order.clientName ?? ''}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
                    ],
                  ),
                ),
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
                title: const Text('إدارة الطلبات',
                    style:
                        TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildBody(),
              ),
            ),
          );
  }

  Widget _buildBody() {
    final filtered = _filteredOrders();

    return Column(
      children: [
        // بحث
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
        // فلاتر
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('جديد'),
            _filterChip('تحت التنفيذ'),
            _filterChip('مكتمل'),
            _filterChip('ملغي'),
          ]),
        ),
        const SizedBox(height: 12),
        // القائمة
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style: const TextStyle(fontFamily: 'Cairo')),
                          const SizedBox(height: 12),
                          ElevatedButton(
                              onPressed: _loadOrders,
                              child: const Text('إعادة المحاولة',
                                  style: TextStyle(fontFamily: 'Cairo'))),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? const Center(
                          child: Text('لا توجد طلبات',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.black54)))
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
}
