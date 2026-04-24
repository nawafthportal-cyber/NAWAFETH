import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/notification_model.dart';
import '../services/account_mode_sync_service.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../services/unread_badge_service.dart';
import '../widgets/platform_top_bar.dart';
import 'my_chats_screen.dart';
import 'plans_screen.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with SingleTickerProviderStateMixin {
  static const _tierOrder = ['basic', 'pioneer', 'professional', 'extra'];

  static const _tierIcons = {
    'basic': Icons.star_rounded,
    'pioneer': Icons.rocket_launch_rounded,
    'professional': Icons.workspace_premium_rounded,
    'extra': Icons.diamond_rounded,
  };

  static const _panelTints = {
    'basic': Color(0xFF6D5DF6),
    'pioneer': Color(0xFF0E8F72),
    'professional': Color(0xFFC5842F),
    'extra': Color(0xFFAA4C7D),
  };

  final Set<String> _savingKeys = <String>{};
  final Set<String> _openSections = <String>{'basic'};

  List<NotificationPreference> _preferences = [];
  List<NotificationPreferenceSection> _sections = [];
  String _activeMode = 'client';
  bool _isLoading = true;
  int _chatUnread = 0;
  String? _errorMessage;
  ValueListenable<UnreadBadges>? _badgeHandle;
  late final AnimationController _entranceController;

  int get _enabledCount =>
      _preferences.where((pref) => pref.enabled && !pref.locked).length;

  int get _lockedCount => _preferences.where((pref) => pref.locked).length;

  String get _modeLabel => _activeMode == 'provider' ? 'وضع مزود الخدمة' : 'وضع العميل';

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _loadPreferences();
  }

  @override
  void dispose() {
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    _entranceController.dispose();
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeHandle?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _chatUnread = badges.chats;
    });
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final mode = await AccountModeSyncService.resolveApiMode();
      final payload = await NotificationService.fetchPreferences(mode: mode);
      final prefs = payload.preferences;
      if (!mounted) return;
      _syncOpenSections(prefs.map((pref) => pref.tier));
      setState(() {
        _activeMode = mode;
        _preferences = prefs;
        _sections = payload.sections;
        _isLoading = false;
      });
      _entranceController
        ..reset()
        ..forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل إعدادات الإشعارات';
      });
    }
  }

  void _syncOpenSections(Iterable<String> tiers) {
    final visible = _sortedTiers(tiers.toSet().toList());
    _openSections.removeWhere((key) => !visible.contains(key));
    if (_openSections.isEmpty && visible.isNotEmpty) {
      _openSections.add(visible.contains('basic') ? 'basic' : visible.first);
    }
  }

  Future<void> _togglePreference(
    NotificationPreference pref,
    bool newValue,
  ) async {
    if (pref.locked) {
      _showLockedDialog(pref.lockedReason, tier: pref.tier);
      return;
    }

    setState(() => _savingKeys.add(pref.key));
    final result = await NotificationService.updatePreferences(
      [
        {'key': pref.key, 'enabled': newValue},
      ],
      mode: _activeMode,
    );

    if (!mounted) return;
    setState(() => _savingKeys.remove(pref.key));

    if (result.success) {
      setState(() {
        if (result.preferences.isNotEmpty) {
          _preferences = result.preferences;
          if (result.sections.isNotEmpty) {
            _sections = result.sections;
          }
        } else {
          final index = _preferences.indexWhere((item) => item.key == pref.key);
          if (index >= 0) {
            _preferences[index] = pref.copyWith(enabled: newValue);
          }
        }
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'فشل حفظ الإعداد',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Color(0xFF9B1C1C),
      ),
    );
  }

  Map<String, List<NotificationPreference>> _groupByTier() {
    final grouped = <String, List<NotificationPreference>>{};
    for (final pref in _preferences) {
      grouped.putIfAbsent(pref.tier, () => <NotificationPreference>[]).add(pref);
    }
    return grouped;
  }

  List<String> _sortedTiers(List<String> tiers) {
    if (_sections.isNotEmpty) {
      final available = tiers.toSet();
      final ordered = _sections
          .map((section) => section.key)
          .where(available.contains)
          .toList();
      for (final tier in tiers) {
        if (!ordered.contains(tier)) {
          ordered.add(tier);
        }
      }
      return ordered;
    }

    final sorted = _tierOrder.where(tiers.contains).toList();
    for (final tier in tiers) {
      if (!sorted.contains(tier)) {
        sorted.add(tier);
      }
    }
    return sorted;
  }

  List<NotificationPreference> _sortedPrefsForTier(
    String tier,
    List<NotificationPreference> prefs,
  ) {
    return List<NotificationPreference>.from(prefs);
  }

  void _toggleSection(String tier) {
    setState(() {
      if (_openSections.contains(tier)) {
        _openSections.remove(tier);
      } else {
        _openSections.add(tier);
      }
    });
  }

  String _formatTierLabel(String tier) {
    final section = _sectionForTier(tier);
    if (section != null && section.title.trim().isNotEmpty) {
      return section.title.trim();
    }
    final normalized = tier.trim().toLowerCase();
    if (normalized.isEmpty) return 'إعدادات إضافية';
    return normalized.replaceAll('_', ' ');
  }

  NotificationPreferenceSection? _sectionForTier(String tier) {
    final normalized = tier.trim().toLowerCase();
    for (final section in _sections) {
      if (section.key.trim().toLowerCase() == normalized) {
        return section;
      }
    }
    return null;
  }

  String? _sectionLockedReason(String tier, List<NotificationPreference> prefs) {
    if (_activeMode != 'provider' || tier == 'basic' || prefs.isEmpty) {
      return null;
    }
    if (!prefs.every((pref) => pref.locked)) {
      return null;
    }
    for (final pref in prefs) {
      if (pref.lockedReason.contains('يلزم الاشتراك في الباقة')) {
        return pref.lockedReason;
      }
    }
    for (final pref in prefs) {
      if (pref.lockedReason.isNotEmpty) {
        return pref.lockedReason;
      }
    }
    return null;
  }

  bool _isExtrasLockedDestination({String? tier, String? message}) {
    final normalizedTier = (tier ?? '').trim().toLowerCase();
    final normalizedMessage = (message ?? '').trim();
    return normalizedTier == 'extra' ||
        normalizedMessage.contains('الخدمات الإضافية') ||
        normalizedMessage.contains('بوابة الخدمات الإضافية');
  }

  String _lockedActionLabel({String? tier, String? message}) {
    final isExtras = _isExtrasLockedDestination(tier: tier, message: message);
    return isExtras ? 'عرض الخدمات الإضافية' : 'عرض الباقات';
  }

  Future<void> _openNewAdditionalServicesPage(BuildContext rootContext) async {
    final uri = Uri.parse(ApiClient.baseUrl).resolve('/additional-services/');
    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched && rootContext.mounted) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر فتح صفحة الخدمات الإضافية الجديدة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Color(0xFF9B1C1C),
        ),
      );
    }
  }

  void _showLockedDialog(String reason, {String? tier}) {
    final message = reason.isNotEmpty
        ? reason
        : 'هذه الإشعارات غير متاحة في اشتراكك الحالي.';
    final rootContext = context;
    final isExtrasDestination =
        _isExtrasLockedDestination(tier: tier, message: message);
    final actionLabel = _lockedActionLabel(tier: tier, message: message);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 68,
                width: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2D8),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFC5842F),
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'سبب عدم الإتاحة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B2230),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.7,
                  color: Color(0xFF566173),
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B6F6A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  if (!rootContext.mounted) return;
                  if (isExtrasDestination) {
                    await _openNewAdditionalServicesPage(rootContext);
                    return;
                  }
                  await Navigator.push(
                    rootContext,
                    MaterialPageRoute(builder: (_) => const PlansScreen()),
                  );
                },
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF475467),
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'إغلاق',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final content = _buildBody();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F4EE),
        appBar: PlatformTopBar(
          pageLabel: 'إعدادات الإشعارات',
          showBackButton: canPop,
          showNotificationAction: false,
          chatCount: _chatUnread,
          onChatsTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyChatsScreen()),
            );
            await UnreadBadgeService.refresh(force: true);
          },
        ),
        body: Stack(
          children: [
            const _NotificationSettingsBackdrop(),
            SafeArea(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return RefreshIndicator(
        onRefresh: _loadPreferences,
        color: const Color(0xFF1B6F6A),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: const [
            _NotificationLoadingHero(),
            SizedBox(height: 16),
            _NotificationLoadingPanel(height: 172),
            SizedBox(height: 14),
            _NotificationLoadingPanel(height: 220),
            SizedBox(height: 14),
            _NotificationLoadingPanel(height: 220),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _loadPreferences,
        color: const Color(0xFF1B6F6A),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            _buildErrorState(),
          ],
        ),
      );
    }

    final grouped = _groupByTier();
    final sortedTiers = _sortedTiers(grouped.keys.toList());

    return RefreshIndicator(
      onRefresh: _loadPreferences,
      color: const Color(0xFF1B6F6A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          _buildEntrance(
            delay: 0.0,
            child: _buildHeroCard(),
          ),
          const SizedBox(height: 16),
          _buildEntrance(
            delay: 0.06,
            child: _buildOverviewPanel(),
          ),
          const SizedBox(height: 16),
          if (sortedTiers.isEmpty)
            _buildEntrance(
              delay: 0.12,
              child: _buildEmptyState(),
            )
          else
            ...List<Widget>.generate(sortedTiers.length, (index) {
              final tier = sortedTiers[index];
              final prefs = _sortedPrefsForTier(tier, grouped[tier]!);
              return Padding(
                padding: EdgeInsets.only(bottom: index == sortedTiers.length - 1 ? 0 : 14),
                child: _buildEntrance(
                  delay: 0.12 + (index * 0.05),
                  child: _buildTierPanel(tier, prefs),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF183A37), Color(0xFF24524E), Color(0xFF2D6D68)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22183A37),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: const Text(
                    'إعدادات الإشعارات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'ضبط التنبيهات بالطريقة التي تناسب تدفق عملك اليومي.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 22,
                height: 1.45,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'يمكنك تفعيل ما تحتاجه فقط مع إبقاء التنبيهات المقفلة مرتبطة بالباقات أو بوابة الخدمات الإضافية.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                height: 1.7,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroMetaChip(
                  icon: Icons.check_circle_outline_rounded,
                  label: '$_enabledCount مفعّل',
                ),
                _HeroMetaChip(
                  icon: Icons.layers_outlined,
                  label: '${_preferences.length} إعداد',
                ),
                _HeroMetaChip(
                  icon: Icons.shield_moon_outlined,
                  label: _modeLabel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7E1D7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ملخص سريع',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B2230),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadPreferences,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'تحديث',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1B6F6A),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _OverviewMetricCard(
                    label: 'الإعدادات المفعلة',
                    value: '$_enabledCount',
                    caption: 'من أصل ${_preferences.length}',
                    tint: const Color(0xFF1B6F6A),
                    icon: Icons.notifications_active_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OverviewMetricCard(
                    label: 'الإعدادات المقفلة',
                    value: '$_lockedCount',
                    caption: _activeMode == 'provider'
                        ? 'مرتبطة بالباقات الحالية'
                        : 'تختلف حسب نوع الحساب',
                    tint: const Color(0xFFC5842F),
                    icon: Icons.lock_outline_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5EFE6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _activeMode == 'provider'
                    ? 'عند قفل قسم كامل ستظهر لك رسالة الترقية نفسها المستخدمة في الويب، مع فتح صفحة الباقات أو الخدمات الإضافية بحسب نوع القفل.'
                    : 'الإعدادات هنا تعكس وضع العميل الحالي، ويمكنك السحب للأسفل لإعادة المزامنة مع الخادم في أي وقت.',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  height: 1.75,
                  color: Color(0xFF5D6674),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierPanel(String tier, List<NotificationPreference> prefs) {
    final section = _sectionForTier(tier);
    final tint = _panelTints[tier] ?? const Color(0xFF6D5DF6);
    final isOpen = _openSections.contains(tier);
    final activeCount = prefs.where((pref) => pref.enabled && !pref.locked).length;
    final isFullyLocked = prefs.isNotEmpty && prefs.every((pref) => pref.locked);
    final lockedReason = _sectionLockedReason(tier, prefs);
    final title = _formatTierLabel(tier);
    final description = (section?.description ?? '').trim().isNotEmpty
        ? section!.description.trim()
        : 'إعدادات إضافية مرتبطة بهذا القسم.';
    final icon = _tierIcons[tier] ?? Icons.notifications_active_outlined;
    final noteTitle = section?.noteTitle.trim() ?? '';
    final noteBody = section?.noteBody.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: tint.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            onTap: () => _toggleSection(tier),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: tint, size: 25),
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
                                title,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B2230),
                                ),
                              ),
                            ),
                            if (isFullyLocked)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF2D8),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'مقفلة',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFC5842F),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            height: 1.7,
                            color: Color(0xFF5D6674),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SectionBadge(
                              label: '$activeCount/${prefs.length} مفعّل',
                              tint: tint,
                            ),
                            _SectionBadge(
                              label: tier == 'extra' ? 'بوابة متخصصة' : _modeLabel,
                              tint: const Color(0xFF7A8699),
                              subdued: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: tint,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  children: [
                    if (lockedReason != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: tint.withValues(alpha: 0.12)),
                        ),
                        child: Text(
                          lockedReason,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            height: 1.7,
                            fontWeight: FontWeight.w700,
                            color: tint,
                          ),
                        ),
                      ),
                    ],
                    ...prefs.map((pref) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildPreferenceTile(pref, tint: tint),
                        )),
                    if (noteTitle.isNotEmpty || noteBody.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F2F7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE9D1DD)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.south_rounded,
                                  color: Color(0xFFAA4C7D),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  noteTitle,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF7F2E5D),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              noteBody,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                height: 1.7,
                                color: Color(0xFF5D6674),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState:
                  isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 240),
              sizeCurve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceTile(
    NotificationPreference pref, {
    required Color tint,
  }) {
    final isSaving = _savingKeys.contains(pref.key);
    final isLocked = pref.locked;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isLocked ? () => _showLockedDialog(pref.lockedReason, tier: pref.tier) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isLocked ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDFBF7),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isLocked
                    ? const Color(0xFFE7D7BB)
                    : tint.withValues(alpha: pref.enabled ? 0.24 : 0.12),
              ),
            ),
            child: Row(
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
                              pref.title,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isLocked
                                    ? const Color(0xFF8D929C)
                                    : const Color(0xFF1B2230),
                              ),
                            ),
                          ),
                          if (pref.enabled && !isLocked)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: tint.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'مفعّل',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: tint,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLocked
                            ? (pref.lockedReason.isNotEmpty
                                ? pref.lockedReason
                                : 'غير متاح في الاشتراك الحالي.')
                            : pref.enabled
                                ? 'سيصلك هذا التنبيه عند تحقق الحدث المرتبط به.'
                                : 'تم إيقاف هذا التنبيه ويمكنك إعادة تفعيله في أي وقت.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          height: 1.7,
                          color: isLocked
                              ? const Color(0xFFB1780D)
                              : const Color(0xFF667085),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                if (isSaving)
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
                      valueColor: AlwaysStoppedAnimation<Color>(tint),
                    ),
                  )
                else if (isLocked)
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2D8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFFC5842F),
                      size: 20,
                    ),
                  )
                else
                  Transform.scale(
                    scale: 0.88,
                    child: Switch.adaptive(
                      value: pref.enabled,
                      activeThumbColor: tint,
                      activeTrackColor: tint.withValues(alpha: 0.35),
                      onChanged: isSaving ? null : (value) => _togglePreference(pref, value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7E1D7)),
      ),
      child: Column(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFB42318),
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'تعذر تحميل الإعدادات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2230),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'حدث خطأ غير متوقع.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.7,
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _loadPreferences,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'إعادة المحاولة',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B6F6A),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7E1D7)),
      ),
      child: Column(
        children: const [
          Icon(
            Icons.notifications_off_outlined,
            size: 34,
            color: Color(0xFF98A2B3),
          ),
          SizedBox(height: 12),
          Text(
            'لا توجد إعدادات متاحة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2230),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'عند توفر إعدادات جديدة من الخادم ستظهر هنا تلقائيًا بعد التحديث.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.7,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntrance({required double delay, required Widget child}) {
    final begin = 0.1 + delay;
    final end = (begin + 0.42).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, builtChild) {
          final offset = 22 * (1 - animation.value);
          return Transform.translate(
            offset: Offset(0, offset),
            child: builtChild,
          );
        },
      ),
    );
  }
}

class _NotificationSettingsBackdrop extends StatelessWidget {
  const _NotificationSettingsBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF7F4EE),
            ),
          ),
          Positioned(
            top: -90,
            right: -50,
            child: Container(
              height: 240,
              width: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B6F6A).withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: -70,
            child: Container(
              height: 210,
              width: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC5842F).withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  const _HeroMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.tint,
    required this.icon,
  });

  final String label;
  final String value;
  final String caption;
  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tint, size: 18),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2230),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF344054),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  const _SectionBadge({
    required this.label,
    required this.tint,
    this.subdued = false,
  });

  final String label;
  final Color tint;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final background = subdued ? const Color(0xFFF4F5F7) : tint.withValues(alpha: 0.10);
    final foreground = subdued ? const Color(0xFF667085) : tint;
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
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _NotificationLoadingHero extends StatelessWidget {
  const _NotificationLoadingHero();

  @override
  Widget build(BuildContext context) {
    return const _NotificationLoadingPanel(height: 226, radius: 30);
  }
}

class _NotificationLoadingPanel extends StatelessWidget {
  const _NotificationLoadingPanel({required this.height, this.radius = 28});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE7E1D7)),
      ),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFF1B6F6A),
          ),
        ),
      ),
    );
  }
}
