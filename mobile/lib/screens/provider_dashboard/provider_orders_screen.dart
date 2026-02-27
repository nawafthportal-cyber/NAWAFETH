import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/provider_order.dart';
import '../../services/marketplace_api.dart';
import '../../services/role_controller.dart';
import '../../services/web_inline_banner.dart';
import '../../services/web_loading_overlay.dart';
import '../client_orders_screen.dart';
import 'provider_order_details_web_entry_screen.dart';
import 'provider_order_details_screen.dart';

/// صفحة تتبع الطلبات الخاصة بمزود الخدمة
/// ====================================
/// هذه الصفحة مخصصة فقط لمزودي الخدمة لرؤية وإدارة طلباتهم.
///
/// التبويبات الثلاثة:
/// 1. طلباتي (Assigned): الطلبات المُسندة للمزود (مرتبطة بـ /marketplace/provider/requests/)
/// 2. العاجلة المتاحة (Urgent Available): الطلبات العاجلة التي يمكن قبولها (مرتبطة بـ /marketplace/provider/urgent/available/)
/// 3. العروض المتاحة (Competitive Available): طلبات العروض التنافسية (مرتبطة بـ /marketplace/provider/competitive/available/)
///
/// ملاحظة مهمة: هذه الصفحة منفصلة تماماً عن ClientOrdersScreen (طلبات العميل)
///
class ProviderOrdersScreen extends StatefulWidget {
  final bool embedded;
  final int initialTabIndex;
  final String? initialSearchQuery;
  final String? initialAssignedStatus;
  final String? initialUrgentStatus;

  const ProviderOrdersScreen({
    super.key,
    this.embedded = false,
    this.initialTabIndex = 0,
    this.initialSearchQuery,
    this.initialAssignedStatus,
    this.initialUrgentStatus,
  });

  @override
  State<ProviderOrdersScreen> createState() => _ProviderOrdersScreenState();
}

class _ProviderOrdersScreenState extends State<ProviderOrdersScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = Colors.deepPurple;

  String _selectedAssignedStatus = 'جديد';
  String _selectedUrgentStatus = 'جديد';

  final TextEditingController _searchController = TextEditingController();

  late final TabController _tabController;

  bool _accountChecked = false;
  bool _isProviderAccount = false;

  bool _loadingAssigned = true;
  bool _loadingUrgent = true;
  bool _loadingCompetitive = true;

  List<Map<String, dynamic>> _assigned = const [];
  List<Map<String, dynamic>> _urgent = const [];
  List<Map<String, dynamic>> _competitive = const [];

  Timer? _searchRouteSyncDebounce;

  @override
  void initState() {
    super.initState();
    _selectedAssignedStatus = _normalizeStatusLabel(widget.initialAssignedStatus);
    _selectedUrgentStatus = _normalizeStatusLabel(widget.initialUrgentStatus);
    _searchController.text = (widget.initialSearchQuery ?? '').trim();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(_onTabChangedForWebUrl);
    _searchController.addListener(() {
      if (mounted) setState(() {});
      _scheduleWebOrdersUrlSync();
    });
    _ensureProviderAccount();
  }

  @override
  void dispose() {
    _searchRouteSyncDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureProviderAccount() async {
    final role = RoleController.instance.notifier.value;
    if (!mounted) return;
    setState(() {
      _isProviderAccount = role.isProvider;
      _accountChecked = true;
    });

    if (!_isProviderAccount) {
      if (widget.embedded) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ClientOrdersScreen()),
        );
      });
      return;
    }

    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_fetchAssigned(), _fetchUrgent(), _fetchCompetitive()]);
  }

  Future<void> _refreshAllWithOverlay() {
    return WebLoadingOverlayController.instance.run(
      _refreshAll,
      message: 'جاري تحديث طلبات مقدم الخدمة...',
    );
  }

  void _onTabChangedForWebUrl() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    _syncWebOrdersUrl();
  }

  void _scheduleWebOrdersUrlSync() {
    if (!(kIsWeb && widget.embedded)) return;
    _searchRouteSyncDebounce?.cancel();
    _searchRouteSyncDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _syncWebOrdersUrl();
    });
  }

  void _syncWebOrdersUrl() {
    if (!(kIsWeb && widget.embedded)) return;

    String tabValue;
    switch (_tabController.index) {
      case 1:
        tabValue = 'urgent';
        break;
      case 2:
        tabValue = 'competitive';
        break;
      case 0:
      default:
        tabValue = 'assigned';
        break;
    }

    String statusToParam(String label) {
      switch (label.trim()) {
        case 'تحت التنفيذ':
          return 'in_progress';
        case 'مكتمل':
          return 'completed';
        case 'ملغي':
          return 'cancelled';
        case 'جديد':
        default:
          return 'new';
      }
    }

    final query = <String, String>{
      'tab': tabValue,
      if (_searchController.text.trim().isNotEmpty) 'q': _searchController.text.trim(),
      'assigned_status': statusToParam(_selectedAssignedStatus),
      'urgent_status': statusToParam(_selectedUrgentStatus),
    };

    final uri = Uri(path: '/provider_dashboard/orders', queryParameters: query);
    SystemNavigator.routeInformationUpdated(uri: uri, replace: true);
  }

  String _normalizeStatusLabel(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'new':
      case 'جديد':
        return 'جديد';
      case 'in_progress':
      case 'progress':
      case 'تحت التنفيذ':
        return 'تحت التنفيذ';
      case 'completed':
      case 'مكتمل':
        return 'مكتمل';
      case 'cancelled':
      case 'canceled':
      case 'ملغي':
        return 'ملغي';
      default:
        return 'جديد';
    }
  }

  Future<void> _fetchAssigned() async {
    if (!mounted) return;
    setState(() => _loadingAssigned = true);
    try {
      String statusGroup;
      switch (_selectedAssignedStatus) {
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
        default:
          statusGroup = 'new';
          break;
      }

      final list = await MarketplaceApi().getMyProviderRequests(
        statusGroup: statusGroup,
      );
      if (!mounted) return;
      setState(() {
        _assigned = list.cast<Map<String, dynamic>>();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assigned = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingAssigned = false);
    }
  }

  Future<void> _fetchUrgent() async {
    if (!mounted) return;
    setState(() => _loadingUrgent = true);
    try {
      List<dynamic> list;
      if (_selectedUrgentStatus == 'جديد') {
        // الطلبات العاجلة الجديدة المتاحة للمزود
        list = await MarketplaceApi().getAvailableUrgentRequestsForProvider();
      } else {
        // الحالات الأخرى تأتي من الطلبات المسندة للمزود ثم نفلتر العاجل
        String statusGroup;
        switch (_selectedUrgentStatus) {
          case 'تحت التنفيذ':
            statusGroup = 'in_progress';
            break;
          case 'مكتمل':
            statusGroup = 'completed';
            break;
          case 'ملغي':
            statusGroup = 'cancelled';
            break;
          default:
            statusGroup = 'new';
            break;
        }
        final all = await MarketplaceApi().getMyProviderRequests(
          statusGroup: statusGroup,
        );
        list = all.where((e) {
          if (e is! Map) return false;
          final type = (e['request_type'] ?? '').toString().trim().toLowerCase();
          return type == 'urgent';
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _urgent = list.cast<Map<String, dynamic>>();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _urgent = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingUrgent = false);
    }
  }

  Future<void> _fetchCompetitive() async {
    if (!mounted) return;
    setState(() => _loadingCompetitive = true);
    try {
      final list = await MarketplaceApi()
          .getAvailableCompetitiveRequestsForProvider();
      if (!mounted) return;
      setState(() {
        _competitive = list.cast<Map<String, dynamic>>();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _competitive = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingCompetitive = false);
    }
  }

  String _mapStatus(String status) {
    switch ((status).toString().trim().toLowerCase()) {
      case 'open':
      case 'pending':
      case 'new':
      case 'sent':
        return 'جديد';
      case 'accepted':
        return 'بانتظار اعتماد العميل';
      case 'in_progress':
        return 'تحت التنفيذ';
      case 'completed':
        return 'مكتمل';
      case 'cancelled':
      case 'canceled':
      case 'expired':
        return 'ملغي';
      default:
        return 'جديد';
    }
  }

  int? _extractRequestId(Map<String, dynamic> req) {
    final raw = req['id'] ?? req['request_id'];
    if (raw is int) return raw > 0 ? raw : null;
    final text = (raw ?? '').toString().trim();
    final direct = int.tryParse(text);
    if (direct != null && direct > 0) return direct;
    final match = RegExp(r'(\d+)').firstMatch(text);
    if (match == null) return null;
    final extracted = int.tryParse(match.group(1) ?? '');
    if (extracted == null || extracted <= 0) return null;
    return extracted;
  }

  String _statusGroup(Map<String, dynamic> req) {
    final group = (req['status_group'] ?? '').toString().trim().toLowerCase();
    if (group.isNotEmpty) return group;

    final raw = (req['status'] ?? '').toString().trim().toLowerCase();
    if (raw.isNotEmpty) {
      if (raw == 'open' || raw == 'pending' || raw == 'new' || raw == 'sent') {
        return 'new';
      }
      if (raw == 'accepted' || raw == 'in_progress') {
        return 'in_progress';
      }
      if (raw == 'completed') return 'completed';
      if (raw == 'cancelled' || raw == 'canceled' || raw == 'expired') {
        return 'cancelled';
      }
    }

    final label = (req['status_label'] ?? '').toString().trim();
    if (label == 'جديد') return 'new';
    if (label == 'تحت التنفيذ') return 'in_progress';
    if (label == 'مكتمل') return 'completed';
    if (label == 'ملغي') return 'cancelled';

    return 'new';
  }

  ProviderOrder _toProviderOrder(Map<String, dynamic> req) {
    DateTime parseDate(dynamic raw) =>
        DateTime.tryParse((raw ?? '').toString()) ?? DateTime.now();

    final attachmentsRaw = req['attachments'];
    final attachments = <ProviderOrderAttachment>[];
    if (attachmentsRaw is List) {
      for (final item in attachmentsRaw) {
        if (item is! Map) continue;
        final type = (item['file_type'] ?? 'file').toString();
        final url = (item['file_url'] ?? '').toString();
        attachments.add(
          ProviderOrderAttachment(
            name: url.isEmpty ? 'ملف مرفق' : url,
            type: type,
          ),
        );
      }
    }

    final statusAr = (req['status_label'] ?? '').toString().trim().isNotEmpty
        ? (req['status_label'] ?? '').toString().trim()
        : _mapStatus((req['status'] ?? '').toString());

    return ProviderOrder(
      id: '#${(_extractRequestId(req) ?? '').toString()}',
      serviceCode: (req['subcategory_name'] ?? '').toString(),
      createdAt: parseDate(req['created_at']),
      status: statusAr,
      clientName: (req['client_name'] ?? '-').toString(),
      clientHandle: '',
      clientPhone: (req['client_phone'] ?? '').toString(),
      clientCity: (req['city'] ?? '').toString(),
      title: (req['title'] ?? '').toString(),
      details: (req['description'] ?? '').toString(),
      attachments: attachments,
      deliveredAt: DateTime.tryParse((req['delivered_at'] ?? '').toString()),
      actualServiceAmountSR: double.tryParse(
        (req['actual_service_amount'] ?? '').toString(),
      ),
      canceledAt: DateTime.tryParse((req['canceled_at'] ?? '').toString()),
      cancelReason: (req['cancel_reason'] ?? '').toString().trim().isEmpty
          ? null
          : (req['cancel_reason'] ?? '').toString(),
    );
  }

  String _rawStatus(Map<String, dynamic> req) {
    final raw = (req['status'] ?? '').toString().trim().toLowerCase();
    if (raw.isNotEmpty) return raw;
    final group = _statusGroup(req);
    if (group == 'new') return 'new';
    if (group == 'in_progress') return 'in_progress';
    if (group == 'completed') return 'completed';
    if (group == 'cancelled') return 'cancelled';
    return '';
  }

  Color _statusColor(String statusAr) {
    switch (statusAr) {
      case 'مكتمل':
        return Colors.green;
      case 'ملغي':
        return Colors.red;
      case 'بانتظار اعتماد العميل':
      case 'تحت التنفيذ':
        return Colors.orange;
      case 'جديد':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString()) ?? DateTime.now();
    return DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(dt);
  }

  bool _matchesQuery(Map<String, dynamic> item, String query) {
    final q = query.toLowerCase();
    bool match(dynamic v) => (v ?? '').toString().toLowerCase().contains(q);
    return match(item['id']) ||
        match(item['title']) ||
        match(item['subcategory_name']) ||
        match(item['category_name']) ||
        match(item['city']) ||
        match(item['client_phone']);
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> src) {
    final query = _searchController.text.trim();
    if (query.isEmpty) return src;
    return src.where((e) => _matchesQuery(e, query)).toList();
  }

  Widget _chip({
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
          color: selected ? _mainColor.withAlpha(28) : Colors.transparent,
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

  Widget _assignedStatusChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(
            label: 'جديد',
            selected: _selectedAssignedStatus == 'جديد',
            onTap: () {
              setState(() => _selectedAssignedStatus = 'جديد');
              _syncWebOrdersUrl();
              _fetchAssigned();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'تحت التنفيذ',
            selected: _selectedAssignedStatus == 'تحت التنفيذ',
            onTap: () {
              setState(() => _selectedAssignedStatus = 'تحت التنفيذ');
              _syncWebOrdersUrl();
              _fetchAssigned();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'مكتمل',
            selected: _selectedAssignedStatus == 'مكتمل',
            onTap: () {
              setState(() => _selectedAssignedStatus = 'مكتمل');
              _syncWebOrdersUrl();
              _fetchAssigned();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'ملغي',
            selected: _selectedAssignedStatus == 'ملغي',
            onTap: () {
              setState(() => _selectedAssignedStatus = 'ملغي');
              _syncWebOrdersUrl();
              _fetchAssigned();
            },
          ),
        ],
      ),
    );
  }

  Widget _urgentStatusChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(
            label: 'جديد',
            selected: _selectedUrgentStatus == 'جديد',
            onTap: () {
              setState(() => _selectedUrgentStatus = 'جديد');
              _syncWebOrdersUrl();
              _fetchUrgent();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'تحت التنفيذ',
            selected: _selectedUrgentStatus == 'تحت التنفيذ',
            onTap: () {
              setState(() => _selectedUrgentStatus = 'تحت التنفيذ');
              _syncWebOrdersUrl();
              _fetchUrgent();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'مكتمل',
            selected: _selectedUrgentStatus == 'مكتمل',
            onTap: () {
              setState(() => _selectedUrgentStatus = 'مكتمل');
              _syncWebOrdersUrl();
              _fetchUrgent();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'ملغي',
            selected: _selectedUrgentStatus == 'ملغي',
            onTap: () {
              setState(() => _selectedUrgentStatus = 'ملغي');
              _syncWebOrdersUrl();
              _fetchUrgent();
            },
          ),
        ],
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> req, {required bool urgentTab}) {
    final statusLabel = (req['status_label'] ?? '').toString().trim();
    final statusAr = statusLabel.isNotEmpty
        ? statusLabel
        : _mapStatus((req['status'] ?? '').toString());
    final statusColor = _statusColor(statusAr);
    final type = (req['request_type'] ?? '').toString().trim().toLowerCase();
    final isUrgent = type == 'urgent';
    final isCompetitive = type == 'competitive';
    final typeLabel = isUrgent ? 'عاجل' : (isCompetitive ? 'عروض' : 'عادي');
    final typeColor = isUrgent
        ? Colors.redAccent
        : (isCompetitive ? Colors.blueGrey : _mainColor);
    final rawStatus = (req['status'] ?? '').toString().trim().toLowerCase();
    final showStartButton =
        !urgentTab &&
        (rawStatus == 'new' ||
            rawStatus == 'sent' ||
            rawStatus == 'open' ||
            rawStatus == 'pending');

    return GestureDetector(
      onTap: () => _openRequestDetails(req, urgentTab: urgentTab),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '#${_extractRequestId(req) ?? '-'}  ${(req['title'] ?? '').toString()}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      color: typeColor,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    statusAr,
                    style: TextStyle(
                      color: statusColor,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${(req['subcategory_name'] ?? '').toString()} • ${(req['city'] ?? '').toString()}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(req['created_at']),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
                if ((req['client_phone'] ?? '').toString().trim().isNotEmpty)
                  Text(
                    (req['client_phone'] ?? '').toString(),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.black45,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              (req['description'] ?? '').toString(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (showStartButton) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _startRequest(req),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mainColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text(
                        'بدء التنفيذ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _openRequestDetails(req, urgentTab: urgentTab),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text(
                      'تفاصيل الطلب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRequestDetails(
    Map<String, dynamic> req, {
    required bool urgentTab,
  }) async {
    final requestId = _extractRequestId(req);
    if (kIsWeb && widget.embedded && requestId != null && requestId > 0) {
      final navigator = Navigator.of(context, rootNavigator: true);
      bool? changed;
      try {
        changed = await navigator.pushNamed<bool>(
          '/provider_dashboard/orders/$requestId',
        );
      } catch (e) {
        debugPrint('ProviderOrders web detail route fallback: $e');
        if (!mounted) return;
        changed = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => ProviderOrderDetailsWebEntryScreen(requestId: requestId),
          ),
        );
      }
      if (changed == true && mounted) {
        await _refreshAll();
      }
      return;
    }

    Map<String, dynamic> details = req;
    if (requestId != null) {
      final fresh = await MarketplaceApi().getProviderRequestDetail(
        requestId: requestId,
      );
      if (fresh != null) {
        details = {...req, ...fresh};
      }
    }
    if (!mounted) return;
    if (requestId == null || requestId <= 0) {
      WebInlineBannerController.instance.error('رقم الطلب غير صالح.');
      return;
    }
    final order = _toProviderOrder(details);
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderOrderDetailsScreen(
          order: order,
          requestId: requestId,
          rawStatus: _rawStatus(details),
          requestType: (details['request_type'] ?? '').toString(),
          statusLogs: (details['status_logs'] is List)
              ? (details['status_logs'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : const [],
        ),
      ),
    );
    if (changed == true && mounted) {
      await _refreshAllWithOverlay();
    }
  }

  Future<void> _startRequest(Map<String, dynamic> req) async {
    final requestId = _extractRequestId(req);
    if (requestId == null || requestId <= 0) {
      if (!mounted) return;
      WebInlineBannerController.instance.error('رقم الطلب غير صالح.');
      return;
    }

    // تأكيد بدء التنفيذ
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'بدء التنفيذ',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'هل تريد بدء تنفيذ هذا الطلب؟',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _mainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'بدء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true || !mounted) return;

    if (!mounted) return;
    WebInlineBannerController.instance.info(
      'يرجى تعبئة بيانات "تحت التنفيذ" الإلزامية داخل تفاصيل الطلب.',
      duration: const Duration(seconds: 4),
    );
    await _openRequestDetails(req, urgentTab: false);
  }

  Widget _searchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _syncWebOrdersUrl(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'ابحث بالعنوان/التخصص/المدينة...',
                hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopStatChip({
    required IconData icon,
    required String label,
    required String value,
    Color color = _mainColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopRowHeader() {
    TextStyle style = const TextStyle(
      fontFamily: 'Cairo',
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: Colors.black54,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('الطلب', style: style)),
          Expanded(flex: 2, child: Text('النوع', style: style)),
          Expanded(flex: 2, child: Text('الحالة', style: style)),
          Expanded(flex: 2, child: Text('المدينة', style: style)),
          Expanded(flex: 2, child: Text('التاريخ', style: style)),
          const SizedBox(width: 88),
        ],
      ),
    );
  }

  Widget _requestDesktopRow(Map<String, dynamic> req, {required bool urgentTab}) {
    final statusLabel = (req['status_label'] ?? '').toString().trim();
    final statusAr = statusLabel.isNotEmpty
        ? statusLabel
        : _mapStatus((req['status'] ?? '').toString());
    final statusColor = _statusColor(statusAr);
    final type = (req['request_type'] ?? '').toString().trim().toLowerCase();
    final isUrgent = type == 'urgent';
    final isCompetitive = type == 'competitive';
    final typeLabel = isUrgent ? 'عاجل' : (isCompetitive ? 'عروض' : 'عادي');
    final typeColor = isUrgent
        ? Colors.redAccent
        : (isCompetitive ? Colors.blueGrey : _mainColor);
    final rawStatus = (req['status'] ?? '').toString().trim().toLowerCase();
    final showStartButton =
        !urgentTab &&
        (rawStatus == 'new' ||
            rawStatus == 'sent' ||
            rawStatus == 'open' ||
            rawStatus == 'pending');
    final id = _extractRequestId(req);
    final title = (req['title'] ?? '').toString().trim();
    final sub = (req['subcategory_name'] ?? '').toString().trim();
    final city = (req['city'] ?? '').toString().trim();
    final dateLabel = _formatDate(req['created_at']);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${id ?? '-'} ${title.isEmpty ? 'طلب خدمة' : title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: typeColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: typeColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  statusAr,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              city.isEmpty ? '-' : city,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showStartButton)
                IconButton(
                  tooltip: 'بدء التنفيذ',
                  onPressed: () => _startRequest(req),
                  icon: const Icon(Icons.play_circle_outline, color: _mainColor),
                ),
              IconButton(
                tooltip: 'تفاصيل الطلب',
                onPressed: () => _openRequestDetails(req, urgentTab: urgentTab),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopTabLayout({
    required List<Map<String, dynamic>> filtered,
    required List<Map<String, dynamic>> rawList,
    required bool isAssigned,
    required bool isUrgent,
    required bool isCompetitive,
  }) {
    final title = isUrgent
        ? 'الطلبات العاجلة'
        : (isCompetitive ? 'عروض الأسعار المتاحة' : 'الطلبات المسندة');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _desktopStatChip(
              icon: Icons.list_alt_rounded,
              label: 'إجمالي النتائج',
              value: filtered.length.toString(),
            ),
            _desktopStatChip(
              icon: Icons.dataset_outlined,
              label: 'المصدر',
              value: rawList.length.toString(),
              color: Colors.blueGrey,
            ),
            if (_searchController.text.trim().isNotEmpty)
              _desktopStatChip(
                icon: Icons.search_rounded,
                label: 'بحث',
                value: 'مفعل',
                color: Colors.orange,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _searchBar(),
        const SizedBox(height: 12),
        if (isAssigned) _assignedStatusChips(),
        if (isAssigned) const SizedBox(height: 12),
        if (isUrgent) _urgentStatusChips(),
        if (isUrgent) const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                _emptyState(
                  isUrgent
                      ? 'لا توجد طلبات عاجلة متاحة حالياً'
                      : (isCompetitive
                          ? 'لا توجد طلبات عروض متاحة حالياً'
                          : 'لا توجد طلبات حالياً'),
                  isUrgent
                      ? 'تأكد من تفعيل الطلبات العاجلة واختيار تخصصاتك في إكمال الملف التعريفي.'
                      : (isCompetitive
                          ? 'ستظهر هنا طلبات العروض المطابقة لتخصصك ومدينتك لتقديم عروضك.'
                          : 'ستظهر الطلبات هنا عندما يتم إسنادها لك.'),
                )
              else ...[
                _desktopRowHeader(),
                ...filtered.map((e) => _requestDesktopRow(e, urgentTab: isUrgent)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabBody({required int tabIndex}) {
    final isAssigned = tabIndex == 0;
    final isUrgent = tabIndex == 1;
    final isCompetitive = tabIndex == 2;

    final loading = isAssigned
        ? _loadingAssigned
        : (isUrgent ? _loadingUrgent : _loadingCompetitive);
    final list = isAssigned ? _assigned : (isUrgent ? _urgent : _competitive);
    final filtered = _filtered(list);

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final desktopLike = widget.embedded &&
        MediaQuery.of(context).size.width >= 980;

    return RefreshIndicator(
      onRefresh: isAssigned
          ? _fetchAssigned
          : (isUrgent ? _fetchUrgent : _fetchCompetitive),
      child: desktopLike
          ? _desktopTabLayout(
              filtered: filtered,
              rawList: list,
              isAssigned: isAssigned,
              isUrgent: isUrgent,
              isCompetitive: isCompetitive,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!widget.embedded) _searchBar(),
                if (!widget.embedded) const SizedBox(height: 12),
                if (isAssigned) _assignedStatusChips(),
                if (isAssigned) const SizedBox(height: 12),
                if (isUrgent) _urgentStatusChips(),
                if (isUrgent) const SizedBox(height: 12),
                if (filtered.isEmpty)
                  _emptyState(
                    isUrgent
                        ? 'لا توجد طلبات عاجلة متاحة حالياً'
                        : (isCompetitive
                              ? 'لا توجد طلبات عروض متاحة حالياً'
                              : 'لا توجد طلبات حالياً'),
                    isUrgent
                        ? 'تأكد من تفعيل الطلبات العاجلة واختيار تخصصاتك في إكمال الملف التعريفي.'
                        : (isCompetitive
                              ? 'ستظهر هنا طلبات العروض المطابقة لتخصصك ومدينتك لتقديم عروضك.'
                              : 'ستظهر الطلبات هنا عندما يتم إسنادها لك.'),
                  )
                else
                  ...filtered.map((e) => _requestCard(e, urgentTab: isUrgent)),
              ],
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
      if (widget.embedded) return const SizedBox.shrink();
      return const Scaffold(body: SizedBox.shrink());
    }

    if (widget.embedded) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Container(
              color: _mainColor,
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                labelColor: _mainColor,
                unselectedLabelColor: Colors.white,
                labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'طلب مباشر'),
                  Tab(text: 'طلب عاجل'),
                  Tab(text: 'عروض أسعار'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _tabBody(tabIndex: 0),
                  _tabBody(tabIndex: 1),
                  _tabBody(tabIndex: 2),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: _mainColor,
          foregroundColor: Colors.white,
          title: const Text(
            'إدارة الطلبات',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refreshAllWithOverlay,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 6,
            ),
            labelColor: _mainColor,
            unselectedLabelColor: Colors.white,
            labelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
            ),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'طلب مباشر'),
              Tab(text: 'طلب عاجل'),
              Tab(text: 'عروض أسعار'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _tabBody(tabIndex: 0),
            _tabBody(tabIndex: 1),
            _tabBody(tabIndex: 2),
          ],
        ),
      ),
    );
  }
}
