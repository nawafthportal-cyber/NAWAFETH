import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/account_mode_service.dart';
import '../services/api_client.dart';
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

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  List<NotificationPreference> _preferences = [];
  String _activeMode = 'client';
  bool _isLoading = true;
  int _chatUnread = 0;
  String? _errorMessage;
  final Set<String> _savingKeys = {};
  ValueListenable<UnreadBadges>? _badgeHandle;

  // ─── Backend tier names ───
  static const _tierOrder = ['basic', 'pioneer', 'professional', 'extra'];

  static const _tierLabels = {
    'basic': 'الباقة الأساسية',
    'pioneer': 'الباقة الريادية',
    'professional': 'الباقة الاحترافية',
    'extra': 'تنبيهات الخدمات الإضافية',
  };

  static const _tierIcons = {
    'basic': Icons.star,
    'pioneer': Icons.rocket_launch,
    'professional': Icons.auto_awesome,
    'extra': Icons.diamond,
  };

  @override
  void initState() {
    super.initState();
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _initModeAndLoad();
  }

  @override
  void dispose() {
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeHandle?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _chatUnread = badges.chats;
    });
  }

  Future<void> _initModeAndLoad() async {
    final mode = await AccountModeService.apiMode();
    if (!mounted) return;
    setState(() => _activeMode = mode);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await NotificationService.fetchPreferences(mode: _activeMode);
      if (!mounted) return;
      setState(() {
        _preferences = prefs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل تحميل الإعدادات';
      });
    }
  }

  // ─── تحديث تفضيل واحد ───
  Future<void> _togglePreference(NotificationPreference pref, bool newVal) async {
    if (pref.locked) {
      _showLockedDialog(pref.lockedReason, tier: pref.tier);
      return;
    }

    setState(() => _savingKeys.add(pref.key));

    final result = await NotificationService.updatePreferences([
      {'key': pref.key, 'enabled': newVal},
    ], mode: _activeMode);

    if (!mounted) return;
    setState(() => _savingKeys.remove(pref.key));

    if (result.success) {
      setState(() {
        if (result.preferences.isNotEmpty) {
          _preferences = result.preferences;
        } else {
          final idx = _preferences.indexWhere((p) => p.key == pref.key);
          if (idx >= 0) {
            _preferences[idx] = pref.copyWith(enabled: newVal);
          }
        }
      }); 
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل حفظ الإعداد', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── تجميع التفضيلات حسب الطبقة ───
  Map<String, List<NotificationPreference>> _groupByTier() {
    final grouped = <String, List<NotificationPreference>>{};
    for (final pref in _preferences) {
      grouped.putIfAbsent(pref.tier, () => []);
      grouped[pref.tier]!.add(pref);
    }
    return grouped;
  }

  // ─── عنصر إشعار ───
  Widget _buildSwitchTile(NotificationPreference pref) {
    final isSaving = _savingKeys.contains(pref.key);

    return Opacity(
      opacity: pref.locked ? 0.35 : 1,
      child: SwitchListTile(
        dense: true,
        activeThumbColor: Colors.deepPurple,
        title: Text(
          pref.title,
          style: TextStyle(
            fontFamily: "Cairo",
            fontSize: 14,
            color: pref.locked ? Colors.grey : Colors.black87,
          ),
        ),
        subtitle: pref.locked
            ? Text(
                pref.lockedReason.isNotEmpty ? pref.lockedReason : "غير متاح في الاشتراك الحالي",
                style: const TextStyle(fontFamily: "Cairo", fontSize: 11, color: Colors.orange),
              )
            : null,
        secondary: isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
              )
            : pref.locked
                ? const Icon(Icons.lock_outline, color: Colors.grey, size: 18)
                : null,
        value: pref.enabled,
        onChanged: pref.locked
            ? (_) => _showLockedDialog(pref.lockedReason, tier: pref.tier)
            : isSaving
                ? null
                : (val) => _togglePreference(pref, val),
      ),
    );
  }

  // ─── كارت الباقة ───
  Widget _buildTierCard(String tier, List<NotificationPreference> prefs) {
    final label = _tierLabels[tier] ?? tier;
    final icon = _tierIcons[tier] ?? Icons.notifications;
    final allLocked = prefs.every((p) => p.locked);
    final lockedReason = _sectionLockedReason(tier, prefs);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: tier == 'basic',
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        collapsedIconColor: Colors.deepPurple,
        iconColor: Colors.deepPurple,
        title: Row(
          children: [
            Icon(icon, color: Colors.deepPurple, size: 26),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.deepPurple,
              ),
            ),
            const Spacer(),
            if (allLocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "مقفلة",
                  style: TextStyle(fontFamily: "Cairo", fontSize: 11, color: Colors.orange),
                ),
              ),
            Text(
              '${prefs.where((p) => p.enabled && !p.locked).length}/${prefs.length}',
              style: const TextStyle(fontFamily: "Cairo", fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        children: [
          if (lockedReason != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.14)),
                ),
                child: Text(
                  lockedReason,
                  style: const TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.deepPurple,
                    height: 1.7,
                  ),
                ),
              ),
            ),
          ...prefs.map((p) => _buildSwitchTile(p)),
        ],
      ),
    );
  }

  String? _sectionLockedReason(String tier, List<NotificationPreference> prefs) {
    if (_activeMode != 'provider' || tier == 'basic' || prefs.isEmpty) {
      return null;
    }
    if (!prefs.every((p) => p.locked)) {
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
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── Dialog ترقية ───
  void _showLockedDialog(String reason, {String? tier}) {
    final message = reason.isNotEmpty
        ? reason
        : "هذه الإشعارات غير متاحة في اشتراكك الحالي.";
    final rootContext = context;
    final isExtrasDestination = _isExtrasLockedDestination(tier: tier, message: message);
    final actionLabel = _lockedActionLabel(tier: tier, message: message);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 50),
              const SizedBox(height: 12),
              const Text(
                "سبب عدم الإتاحة",
                style: TextStyle(
                  fontFamily: "Cairo",
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        if (!rootContext.mounted) return;
                        if (isExtrasDestination) {
                          await _openNewAdditionalServicesPage(rootContext);
                          return;
                        }
                        Navigator.push(
                          rootContext,
                          MaterialPageRoute(builder: (_) => const PlansScreen()),
                        );
                      },
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          fontFamily: "Cairo",
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.deepPurple),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "إغلاق",
                        style: TextStyle(fontFamily: "Cairo", fontSize: 14, color: Colors.deepPurple),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: PlatformTopBar(
          pageLabel: 'إعدادات الإشعارات',
          showBackButton: canPop,
          showNotificationAction: false,
          chatCount: _chatUnread,
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
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadPreferences,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                          child: const Text("إعادة المحاولة",
                              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadPreferences,
                    color: Colors.deepPurple,
                    child: Builder(
                      builder: (context) {
                        final grouped = _groupByTier();
                        final sortedTiers = _tierOrder.where((t) => grouped.containsKey(t)).toList();
                        // أي طبقة غير معروفة في النهاية
                        for (final t in grouped.keys) {
                          if (!sortedTiers.contains(t)) sortedTiers.add(t);
                        }

                        if (sortedTiers.isEmpty) {
                          return const Center(
                            child: Text("لا توجد إعدادات متاحة",
                                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                          );
                        }

                        return ListView(
                          children: sortedTiers
                              .map((tier) => _buildTierCard(tier, grouped[tier]!))
                              .toList(),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
