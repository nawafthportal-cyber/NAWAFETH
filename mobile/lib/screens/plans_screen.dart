import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/subscriptions_service.dart';
import '../widgets/platform_top_bar.dart';
import 'login_screen.dart';
import 'plan_summary_screen.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  static const List<String> _planOrder = <String>['basic', 'riyadi', 'pro'];

  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _currentSubscription;
  String _accountDisplayName = 'حساب مقدم الخدمة';
  bool _isLoggedIn = true;
  bool _loading = true;
  String? _error;

  static const List<String> _preferredTextKeys = <String>[
    'ar',
    'text',
    'label',
    'title',
    'name',
    'value',
    'display_name',
    'display',
    'value_text',
    'display_value',
    'message',
    'en',
  ];

  String _displayText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;

    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? fallback : text;
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is List) {
      final parts = value
          .map((item) => _displayText(item))
          .where((item) => item.isNotEmpty)
          .toList();
      return parts.isEmpty ? fallback : parts.join('، ');
    }

    if (value is Map) {
      for (final key in _preferredTextKeys) {
        if (value.containsKey(key)) {
          final text = _displayText(value[key]);
          if (text.isNotEmpty) return text;
        }
      }

      for (final entry in value.entries) {
        final text = _displayText(entry.value);
        if (text.isNotEmpty) return text;
      }

      return fallback;
    }

    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = _displayText(value).toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  List<Map<String, dynamic>> _rowsForPlan(Map<String, dynamic> plan) {
    final offer = SubscriptionsService.planOffer(plan);
    final rows = offer['card_rows'];
    if (rows is List) {
      final normalized = rows
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return _comparisonFallbackRows(plan);
  }

  Map<String, dynamic> _actionForPlan(Map<String, dynamic> plan) {
    return SubscriptionsService.planAction(plan);
  }

  String _statusBadgeText(Map<String, dynamic> action) {
    final state = _displayText(action['state']).toLowerCase();
    switch (state) {
      case 'current':
      case 'pending':
        return _displayText(action['label']);
      case 'unavailable':
        return 'باقة أقل من الحالية';
      default:
        return '';
    }
  }

  List<Color> _gradientForTier(Map<String, dynamic> plan) {
    final tier = _canonicalTier(plan);
    switch (tier) {
      case 'professional':
      case 'pro':
        return const [Color(0xFF123C32), Color(0xFF0F766E)];
      case 'pioneer':
      case 'riyadi':
        return const [Color(0xFF0F4C5C), Color(0xFF2A9D8F)];
      default:
        return const [Color(0xFF5F6F52), Color(0xFFA3B18A)];
    }
  }

  String _canonicalTier(Map<String, dynamic> plan) {
    return _displayText(
      plan['canonical_tier'] ?? SubscriptionsService.planOffer(plan)['tier'],
    ).toLowerCase();
  }

  List<Map<String, dynamic>> _orderedPlans(List<Map<String, dynamic>> plans) {
    final ordered = List<Map<String, dynamic>>.from(plans);
    ordered.sort((left, right) {
      final leftIndex = _planOrder.indexOf(_canonicalTier(left));
      final rightIndex = _planOrder.indexOf(_canonicalTier(right));
      final normalizedLeft = leftIndex == -1 ? 999 : leftIndex;
      final normalizedRight = rightIndex == -1 ? 999 : rightIndex;
      return normalizedLeft.compareTo(normalizedRight);
    });
    return ordered;
  }

  Map<String, dynamic> _capabilitiesForPlan(Map<String, dynamic> plan) {
    final raw = plan['capabilities'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _promotionalControlsForPlan(Map<String, dynamic> plan) {
    final raw = _capabilitiesForPlan(plan)['promotional_controls'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  String _valueOrDash(dynamic value) {
    return _displayText(value, fallback: '-');
  }

  String _yesNoValue(dynamic value) {
    return _asBool(value) ? 'نعم' : '-';
  }

  String _quotaValue(dynamic value) {
    if (value is num && value > 0) {
      return value.toString();
    }
    final parsed = num.tryParse(_displayText(value));
    if (parsed != null && parsed > 0) {
      return parsed.toString();
    }
    return '-';
  }

  List<Map<String, dynamic>> _comparisonFallbackRows(Map<String, dynamic> plan) {
    final offer = SubscriptionsService.planOffer(plan);
    final capabilities = _capabilitiesForPlan(plan);
    final promotionalControls = _promotionalControlsForPlan(plan);
    final storage = capabilities['storage'];
    final urgentRequests = capabilities['urgent_requests'];
    final competitiveRequests = capabilities['competitive_requests'];
    final bannerImages = capabilities['banner_images'];
    final reminders = capabilities['reminders'];
    final messaging = capabilities['messaging'];
    final support = capabilities['support'];

    return <Map<String, dynamic>>[
      {
        'label': 'جميع الخدمات الأساسية للمنصة كعميل وكمختص',
        'value': 'نعم',
      },
      {
        'label': 'استلام التنبيهات',
        'value': _yesNoValue(capabilities['notifications_enabled']),
      },
      {
        'label': 'السعة التخزينية المتاحة',
        'value': _valueOrDash(storage is Map ? storage['label'] : null),
      },
      {
        'label': 'استقبال الطلبات العاجلة',
        'value': _valueOrDash(
          urgentRequests is Map ? urgentRequests['visibility_label'] : null,
        ),
      },
      {
        'label': 'استقبال طلبات الخدمات التنافسية',
        'value': _valueOrDash(
          competitiveRequests is Map
              ? competitiveRequests['visibility_label']
              : null,
        ),
      },
      {
        'label': 'صور شعار المنصة (Banner)',
        'value': _valueOrDash(bannerImages is Map ? bannerImages['label'] : null),
      },
      {
        'label': 'التحكم برسائل المحادثات الدعائية',
        'value': _yesNoValue(promotionalControls['chat_messages']),
      },
      {
        'label': 'التحكم برسائل التنبيه الدعائية',
        'value': _yesNoValue(promotionalControls['notification_messages']),
      },
      {
        'label': 'إرسال رسائل تنبيه للعملاء لتقييم الخدمة',
        'value': _valueOrDash(reminders is Map ? reminders['label'] : null),
      },
      {
        'label': 'عدد المحادثات المباشرة',
        'value': _quotaValue(
          messaging is Map ? messaging['direct_chat_quota'] : null,
        ),
      },
      {
        'label': 'التوثيق (شارة زرقاء)',
        'value': _valueOrDash(offer['verification_blue_label']),
      },
      {
        'label': 'التوثيق (شارة خضراء)',
        'value': _valueOrDash(offer['verification_green_label']),
      },
      {
        'label': 'الدعم الفني',
        'value': _valueOrDash(support is Map ? support['sla_label'] : null),
      },
      {
        'label': 'سعر الاشتراك السنوي',
        'value': _valueOrDash(
          offer['final_payable_label'] ?? offer['annual_price_label'],
        ),
      },
    ];
  }

  String get _currentPlanTitle =>
      SubscriptionsService.planTitleFromSubscription(_currentSubscription);

  String get _currentStatusLabel {
    final statusCode = _displayText(
      _currentSubscription?['provider_status_code'] ??
          _currentSubscription?['status'],
    );
    if (statusCode.isEmpty) {
      return 'جاهز للترقية';
    }
    return SubscriptionsService.subscriptionStatusLabel(statusCode);
  }

  String get _heroPillLabel => _accountDisplayName;

  String get _heroNote {
    if (_currentSubscription == null) {
      return 'اختر الباقة المناسبة لإكمال الترقية والاستفادة من جميع المزايا.';
    }

    final endAt = SubscriptionsService.parseSubscriptionEndAt(_currentSubscription);
    final untilLabel = endAt == null ? '' : ' حتى ${_formatDate(endAt)}';
    return 'باقتك الحالية: $_currentPlanTitle. حالة الاشتراك: $_currentStatusLabel$untilLabel. اختر الترقية المناسبة أو راجع باقتك الحالية.';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  bool _looksLikePhone(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s\-\+\(\)@]'), '');
    return RegExp(r'^0\d{8,12}$').hasMatch(normalized) ||
        RegExp(r'^9665\d{8}$').hasMatch(normalized) ||
        RegExp(r'^5\d{8}$').hasMatch(normalized);
  }

  String _safeAccountName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || _looksLikePhone(text)) {
      return '';
    }
    return text;
  }

  Future<String> _loadAccountDisplayName() async {
    try {
      final result = await ProfileService.fetchMyProfile();
      final profile = result.data;
      if (!result.isSuccess || profile == null) {
        return 'حساب مقدم الخدمة';
      }
      final candidates = <String>[
        _safeAccountName(profile.providerDisplayName),
        _safeAccountName(profile.displayName),
        _safeAccountName(profile.username),
      ];
      for (final candidate in candidates) {
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }
      return 'حساب مقدم الخدمة';
    } catch (_) {
      return 'حساب مقدم الخدمة';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final isLoggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;

    if (!isLoggedIn) {
      setState(() {
        _isLoggedIn = false;
        _plans = const [];
        _currentSubscription = null;
        _accountDisplayName = 'حساب مقدم الخدمة';
        _loading = false;
      });
      return;
    }

    try {
      final plansFuture = SubscriptionsService.getPlans();
      final subscriptionsFuture = SubscriptionsService.mySubscriptions();
      final accountDisplayNameFuture = _loadAccountDisplayName();

      final plans = await plansFuture;
      final subscriptions = await subscriptionsFuture;
      final accountDisplayName = await accountDisplayNameFuture;
      final preferredSubscription =
          SubscriptionsService.selectPreferredSubscription(subscriptions);
      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
        _plans = _orderedPlans(plans);
        _currentSubscription = preferredSubscription;
        _accountDisplayName = accountDisplayName;
        _loading = false;
        if (plans.isEmpty) {
          _error = 'لا توجد باقات متاحة حالياً';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
        _plans = const [];
        _currentSubscription = null;
        _accountDisplayName = 'حساب مقدم الخدمة';
        _loading = false;
        _error = 'تعذر تحميل الباقات حالياً';
      });
    }
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(redirectTo: PlansScreen()),
      ),
    );
    if (!mounted) return;
    await _loadPlans();
  }

  Future<void> _openSummary(Map<String, dynamic> plan) async {
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlanSummaryScreen(plan: plan),
      ),
    );
    if (refreshed == true && mounted) {
      await _loadPlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth <= 390;
    final veryCompact = screenWidth <= 360;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        appBar: const PlatformTopBar(
          pageLabel: 'باقات اشتراك مقدم الخدمة',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_isLoggedIn
                ? _buildAuthGate(compact: compact)
                : Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 12,
                          compact ? 10 : 14,
                          compact ? 10 : 12,
                          0,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 20,
                            compact ? 18 : 22,
                            compact ? 16 : 20,
                            compact ? 18 : 22,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF673AB7),
                                Color(0xFF4A2D8F),
                                Color(0xFF3A1F73),
                              ],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x403A1F73),
                                blurRadius: 28,
                                offset: Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.30),
                                  ),
                                ),
                                child: Text(
                                  _heroPillLabel,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 14 : 16),
                              const Text(
                                'باقات الاشتراك',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _heroNote,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xE0FFFFFF),
                                  height: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: _error != null
                            ? Center(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 12 : 16,
                                    compact ? 12 : 14,
                                    compact ? 12 : 16,
                                    compact ? 18 : 22,
                                  ),
                                  child: _buildStateCard(
                                    message: _error!,
                                    compact: compact,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 10 : 12,
                                  compact ? 10 : 14,
                                  compact ? 10 : 12,
                                  compact ? 10 : 12,
                                ),
                                itemCount: _plans.length,
                                itemBuilder: (context, index) => _planCard(
                                  _plans[index],
                                  compact: compact,
                                  veryCompact: veryCompact,
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildAuthGate({required bool compact}) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: EdgeInsets.fromLTRB(
            compact ? 22 : 28,
            compact ? 24 : 30,
            compact ? 22 : 28,
            compact ? 24 : 30,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF5F0FB)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD1C4E9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14673AB7),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 62 : 70,
                height: compact ? 62 : 70,
                decoration: BoxDecoration(
                  color: const Color(0x14673AB7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: const Color(0xFF673AB7),
                  size: compact ? 30 : 34,
                ),
              ),
              SizedBox(height: compact ? 16 : 18),
              const Text(
                'تسجيل الدخول مطلوب',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF3A1F73),
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              const Text(
                'يجب تسجيل الدخول لعرض باقات الاشتراك المناسبة لحسابك.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E5A99),
                  height: 1.8,
                ),
              ),
              SizedBox(height: compact ? 18 : 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF673AB7),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: compact ? 14 : 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateCard({
    required String message,
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 460),
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 22 : 26,
        compact ? 18 : 22,
        compact ? 20 : 24,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F0FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD1C4E9)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 52 : 58,
            height: compact ? 52 : 58,
            decoration: BoxDecoration(
              color: const Color(0x14673AB7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: const Color(0xFF673AB7),
              size: compact ? 28 : 30,
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A2D8F),
              height: 1.8,
            ),
          ),
          SizedBox(height: compact ? 16 : 18),
          ElevatedButton(
            onPressed: _loadPlans,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF673AB7),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 20 : 24,
                vertical: compact ? 12 : 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'إعادة المحاولة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(
    Map<String, dynamic> plan, {
    required bool compact,
    required bool veryCompact,
  }) {
    final offer = SubscriptionsService.planOffer(plan);
    final action = _actionForPlan(plan);
    final rows = _rowsForPlan(plan);
    final colors = _gradientForTier(plan);
    final planName = _displayText(
      SubscriptionsService.planDisplayTitle(plan),
      fallback: 'الباقة',
    );
    final description = _displayText(offer['description']);
    final annualPrice = _displayText(
      offer['final_payable_label'] ?? offer['annual_price_label'],
      fallback: 'مجانية',
    );
    final verificationEffect = _displayText(offer['verification_effect_label']);
    final buttonLabel = _displayText(action['label'], fallback: 'ترقية');
    final canOpen = _asBool(action['enabled']);
    final badgeText = _statusBadgeText(action);

    Widget priceChip({required bool fullWidth}) {
      return Container(
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth
            ? null
            : BoxConstraints(minWidth: compact ? 96 : 110),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(34),
          borderRadius: BorderRadius.circular(compact ? 16 : 18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'السعر السنوي',
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 11 : 12,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              annualPrice,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 12 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 20 : 26),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: compact ? 18 : 24,
            offset: Offset(0, compact ? 10 : 14),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (veryCompact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        planName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: veryCompact ? 18 : (compact ? 20 : 24),
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      if (badgeText.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 9 : 10,
                            vertical: compact ? 4 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: colors.last,
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.7,
                      fontSize: compact ? 13 : 14,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  priceChip(fullWidth: true),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              planName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: veryCompact ? 18 : (compact ? 20 : 24),
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            if (badgeText.isNotEmpty)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 9 : 10,
                                  vertical: compact ? 4 : 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(220),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    color: colors.last,
                                    fontSize: compact ? 11 : 12,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.7,
                            fontSize: compact ? 13 : 14,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  priceChip(fullWidth: false),
                ],
              ),
            SizedBox(height: compact ? 14 : 18),
            Container(
              padding: EdgeInsets.all(compact ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(compact ? 16 : 20),
              ),
              child: Column(
                children: rows
                    .map(
                      (row) => Padding(
                        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _displayText(
                                  row['label'] ?? row['title'] ?? row['name'],
                                ),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: compact ? 12 : 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            SizedBox(width: compact ? 10 : 12),
                            Expanded(
                              child: Text(
                                _displayText(
                                  row['value'] ?? row['text'] ?? row['amount'],
                                ),
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            Text(
              'أثر الباقة على التوثيق: $verificationEffect',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.7,
                fontSize: compact ? 13 : 14,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: compact ? 12 : 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canOpen ? () => _openSummary(plan) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: colors.last,
                  disabledBackgroundColor: Colors.white24,
                  disabledForegroundColor: Colors.white70,
                  padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  ),
                ),
                child: Text(
                  buttonLabel,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 14 : 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
