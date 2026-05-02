import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nawafeth/constants/app_theme.dart';
import 'package:nawafeth/widgets/bottom_nav.dart';
import 'package:nawafeth/widgets/custom_drawer.dart';
import 'package:nawafeth/widgets/platform_top_bar.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/interactive_service.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/services/subscriptions_service.dart';
import 'package:nawafeth/services/marketplace_service.dart';
import 'package:nawafeth/services/unread_badge_service.dart';
import 'package:nawafeth/models/user_profile.dart';
import 'package:nawafeth/models/provider_profile_model.dart';
import 'package:nawafeth/models/provider_public_model.dart';
import 'package:nawafeth/screens/notifications_screen.dart';
import 'package:nawafeth/screens/my_chats_screen.dart';

import 'profile_tab.dart';
import 'services_tab.dart';
import 'reviews_tab.dart';
import 'package:nawafeth/screens/provider_dashboard/provider_orders_screen.dart';
import 'package:nawafeth/screens/verification_screen.dart';
import 'package:nawafeth/screens/plans_screen.dart';
import 'package:nawafeth/screens/my_qr_screen.dart';
import 'package:nawafeth/screens/registration/steps/content_step.dart';
import 'package:nawafeth/screens/provider_dashboard/promotion_screen.dart';
import 'package:nawafeth/screens/provider_dashboard/provider_profile_completion_screen.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  final Color mainColor = const Color(0xFF5E35B1);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  File? _profileImage;
  File? _coverImage;

  bool _isLoading = true;
  bool _isUploadingProfileMedia = false;
  bool _isUploadingSpotlight = false;
  String? _errorMessage;

  UserProfile? _userProfile;
  ProviderProfileModel? _providerProfile;
  ProviderPublicModel? _providerPublicFallback;
  String? _subscriptionPlanName;
  String? _subscriptionStatus;
  DateTime? _subscriptionEndAt;
  bool _subscriptionLoaded = false;
  bool _hasSelectedSubscription = false;
  int _urgentOrdersCount = 0;
  int _newOrdersCount = 0;
  int _competitiveOrdersCount = 0;
  int _clientsCount = 0;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  ValueListenable<UnreadBadges>? _badgeListenable;
  Map<String, dynamic>? _providerStats;
  List<Map<String, dynamic>> _mySpotlights = <Map<String, dynamic>>[];
  final Set<int> _deletingSpotlightIds = <int>{};

  String get _currentPlanName => _subscriptionPlanName ?? "الباقة المجانية";
  String? get _currentPlanStatusLabel => _subscriptionStatus == null
      ? null
      : SubscriptionsService.subscriptionStatusLabel(_subscriptionStatus);
  int? _providerStatIntOrNull(String key) {
    final value = _providerStats?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  int get _followersCount =>
      _providerStatIntOrNull('followers_count') ??
      _userProfile?.providerFollowersCount ??
      0;

  int get _followingCount =>
      _providerStatIntOrNull('following_count') ??
      _userProfile?.followingCount ??
      0;

  int get _likesReceivedCount =>
      _providerStatIntOrNull('media_likes_count') ??
      _providerStatIntOrNull('likes_count') ??
      _userProfile?.providerLikesReceivedCount ??
      0;

  int get _savedByUsersCount =>
      _providerStatIntOrNull('media_saves_count') ?? 0;

    bool get _isSpotlightUploadLocked =>
      _subscriptionLoaded && !_hasSelectedSubscription;

  String get _providerDisplayName {
    final providerName = (_providerProfile?.displayName ?? '').trim();
    if (providerName.isNotEmpty) return providerName;

    final publicName = (_providerPublicFallback?.displayName ?? '').trim();
    if (publicName.isNotEmpty) return publicName;

    final fallbackProvider = (_userProfile?.providerDisplayName ?? '').trim();
    if (fallbackProvider.isNotEmpty) return fallbackProvider;

    final userName = (_userProfile?.displayName ?? '').trim();
    return userName.isEmpty ? 'مزود الخدمة' : userName;
  }

  String get _providerUsernameLabel {
    final publicUsername = (_providerPublicFallback?.username ?? '').trim();
    if (publicUsername.isNotEmpty) {
      return publicUsername.startsWith('@') ? publicUsername : '@$publicUsername';
    }

    final value = (_userProfile?.usernameDisplay ?? '').trim();
    return value.isEmpty ? '@provider' : value;
  }

  Future<void> _openNewAdditionalServicesPage() async {
    final uri = Uri.parse(ApiClient.baseUrl).resolve('/additional-services/');
    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح صفحة الخدمات الإضافية الجديدة')),
      );
    }
  }

  String? get _resolvedProfileImagePath {
    final providerImage = (_providerProfile?.profileImage ?? '').trim();
    if (providerImage.isNotEmpty) return providerImage;

    final publicImage = (_providerPublicFallback?.profileImage ?? '').trim();
    if (publicImage.isNotEmpty) return publicImage;

    final userImage = (_userProfile?.profileImage ?? '').trim();
    return userImage.isEmpty ? null : userImage;
  }

  String? get _resolvedCoverImagePath {
    final providerCover = (_providerProfile?.coverImage ?? '').trim();
    if (providerCover.isNotEmpty) return providerCover;

    final publicCover = (_providerPublicFallback?.coverImage ?? '').trim();
    if (publicCover.isNotEmpty) return publicCover;

    final userCover = (_userProfile?.coverImage ?? '').trim();
    return userCover.isEmpty ? null : userCover;
  }

  bool get _isProviderVerifiedBlue =>
      _providerProfile?.isVerifiedBlue == true ||
      _providerPublicFallback?.isVerifiedBlue == true;

  bool get _isProviderVerifiedGreen =>
      _providerProfile?.isVerifiedGreen == true ||
      _providerPublicFallback?.isVerifiedGreen == true;

  bool get _hasProviderExcellenceBadges {
    final profileBadges = _providerProfile?.excellenceBadges ?? const [];
    if (profileBadges.isNotEmpty) return true;

    final publicBadges = _providerPublicFallback?.excellenceBadges ?? const [];
    return publicBadges.isNotEmpty;
  }

  // ✅ نسبة إكمال الملف من البيانات الحقيقية
  double get _profileCompletion => _providerProfile?.profileCompletion ?? 0.30;

  @override
  void initState() {
    super.initState();
    _loadProviderData();
    _badgeListenable = UnreadBadgeService.acquire();
    _badgeListenable!.addListener(_handleBadgeChange);
    _handleBadgeChange();
    UnreadBadgeService.refresh(force: true);
  }

  /// ✅ تحميل بيانات المزود من الـ API
  Future<void> _loadProviderData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // نبدأ طلب ملف المزود مبكراً بالتوازي لتقليل زمن الانتظار الكلي.
    final providerFuture = ProfileService.fetchProviderProfile();

    // جلب بيانات المستخدم الأساسية (الحد الأدنى لعرض الشاشة).
    final meResult = await ProfileService.fetchMyProfile();
    if (!mounted) return;

    if (!meResult.isSuccess || meResult.data == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = meResult.error ?? 'خطأ في جلب البيانات';
      });
      return;
    }

    final userProfile = meResult.data!;
    if (!userProfile.hasProviderProfile && !userProfile.isProvider) {
      await AccountModeService.setProviderMode(false);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/profile');
      return;
    }

    setState(() {
      _userProfile = userProfile;
      _isLoading = false;
    });

    // تحميلات ثانوية بالخلفية حتى لا نحجب الشاشة.
    unawaited(_loadProviderProfile(providerFuture));
    unawaited(_loadProviderPublicFallback());
    unawaited(_loadSubscriptionPlan());
    unawaited(_loadOrderCounts());
    unawaited(_loadMySpotlights());
    unawaited(_loadProviderStats());
  }

  Future<void> _loadProviderProfile(
    Future<ProfileResult<ProviderProfileModel>> providerFuture,
  ) async {
    try {
      final providerResult = await providerFuture;
      if (!mounted) return;
      if (providerResult.isSuccess && providerResult.data != null) {
        setState(() {
          _providerProfile = providerResult.data;
        });
        unawaited(_loadProviderStats());
      } else {
        unawaited(_loadProviderPublicFallback());
      }
    } catch (_) {
      unawaited(_loadProviderPublicFallback());
    }
  }

  Future<void> _loadProviderPublicFallback() async {
    try {
      final providerId = _userProfile?.providerProfileId;
      if (providerId == null || providerId <= 0) return;

      final response = await InteractiveService.fetchProviderDetail(providerId);
      if (!mounted || !response.isSuccess || response.dataAsMap == null) return;

      final parsed = ProviderPublicModel.fromJson(response.dataAsMap!);
      if (!mounted) return;
      setState(() {
        _providerPublicFallback = parsed;
      });
    } catch (_) {
      // optional fallback
    }
  }

  Future<void> _loadProviderStats() async {
    try {
      final providerId =
          _providerProfile?.id ?? _userProfile?.providerProfileId;
      if (providerId == null || providerId <= 0) return;
      final response = await InteractiveService.fetchProviderStats(providerId);
      if (!mounted || !response.isSuccess || response.dataAsMap == null) return;
      setState(() {
        _providerStats = response.dataAsMap;
      });
    } catch (_) {
      // optional data
    }
  }

  /// جلب أعداد الطلبات (العاجلة، التنافسية، الجديدة، المكتملة)
  Future<void> _loadOrderCounts() async {
    try {
      final results = await Future.wait([
        MarketplaceService.getAvailableUrgentRequests(),
        MarketplaceService.getAvailableCompetitiveRequests(),
        MarketplaceService.getProviderRequests(statusGroup: 'new'),
        MarketplaceService.getProviderRequests(statusGroup: 'completed'),
      ]);
      if (!mounted) return;
      setState(() {
        _urgentOrdersCount = results[0].length;
        _competitiveOrdersCount = results[1].length;
        _newOrdersCount = results[2].length;
        _clientsCount = results[3].length;
      });
    } catch (_) {
      // non-critical, keep defaults
    }
  }

  /// ✅ جلب اسم الباقة الحالية من الـ API
  Future<void> _loadSubscriptionPlan() async {
    final subs = await SubscriptionsService.mySubscriptions();
    if (!mounted) return;
    final selected = SubscriptionsService.selectPreferredSubscription(subs);
    setState(() {
      _subscriptionLoaded = true;
      _hasSelectedSubscription = selected != null;
      _subscriptionPlanName =
          SubscriptionsService.planTitleFromSubscription(selected);
      _subscriptionStatus =
        selected?['provider_status_code']?.toString() ?? selected?['status']?.toString();
      _subscriptionEndAt =
          SubscriptionsService.parseSubscriptionEndAt(selected);
    });
  }

  @override
  void dispose() {
    _badgeListenable?.removeListener(_handleBadgeChange);
    UnreadBadgeService.release();
    super.dispose();
  }

  Future<void> _loadUnreadBadges() async {
    await UnreadBadgeService.refresh(force: true);
  }

  void _handleBadgeChange() {
    final badges = _badgeListenable?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  // اختيار صورة الغلاف / الصورة الشخصية
  Future<void> _pickImage({required bool isCover}) async {
    if (_isUploadingProfileMedia) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    // عرض معاينة فورية أثناء الرفع.
    setState(() {
      _isUploadingProfileMedia = true;
      if (isCover) {
        _coverImage = File(picked.path);
      } else {
        _profileImage = File(picked.path);
      }
    });

    final result = await ProfileService.uploadProviderProfileImages(
      profileImagePath: isCover ? null : picked.path,
      coverImagePath: isCover ? picked.path : null,
    );
    if (!mounted) return;

    setState(() {
      _isUploadingProfileMedia = false;
      if (isCover) {
        _coverImage = null;
      } else {
        _profileImage = null;
      }

      if (result.isSuccess && result.data != null) {
        _providerProfile = result.data;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? (isCover
                  ? 'تم حفظ صورة الغلاف بنجاح'
                  : 'تم حفظ صورة الحساب بنجاح')
              : (result.error ?? 'تعذر حفظ الصورة'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: result.isSuccess ? AppColors.success : AppColors.error,
      ),
    );

    if (result.isSuccess) {
      // تحديث البيانات العامة المرتبطة بالهيدر بعد الرفع.
      unawaited(_loadProviderProfile(ProfileService.fetchProviderProfile()));
    }
  }

  Future<void> _loadMySpotlights() async {
    try {
      final response = await InteractiveService.fetchMySpotlights();
      if (!mounted) return;
      if (response.isSuccess) {
        final data = response.data;
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : const <dynamic>[]);
        final parsed = list
            .whereType<Map>()
            .map((e) => e.map((key, value) => MapEntry(key.toString(), value)))
            .toList();
        setState(() {
          _mySpotlights = parsed;
        });
      }
    } catch (_) {
      // non-critical
    }
  }

  // اختيار فيديو ريلز
  Future<void> _pickVideo() async {
    if (_isUploadingSpotlight) return;

    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() {
      _isUploadingSpotlight = true;
    });

    final result = await ProfileService.uploadProviderSpotlight(
      filePath: picked.path,
      fileType: 'video',
      caption: 'لمحة',
    );
    if (!mounted) return;

    setState(() {
      _isUploadingSpotlight = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? "تم حفظ اللمحة بنجاح"
              : (result.error ?? "تعذر حفظ اللمحة"),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: result.isSuccess ? AppColors.success : AppColors.error,
      ),
    );

    if (result.isSuccess) {
      unawaited(_loadMySpotlights());
    }
  }

  Future<void> _deleteSpotlight(int itemId) async {
    if (_deletingSpotlightIds.contains(itemId)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف اللمحة', style: TextStyle(fontFamily: 'Cairo')),
        content: const Text(
          'هل تريد حذف هذه اللمحة؟',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'حذف',
              style: TextStyle(fontFamily: 'Cairo', color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _deletingSpotlightIds.add(itemId);
    });

    final response = await InteractiveService.deleteSpotlightItem(itemId);
    if (!mounted) return;

    setState(() {
      _deletingSpotlightIds.remove(itemId);
      if (response.isSuccess) {
        _mySpotlights.removeWhere((item) => _toInt(item['id']) == itemId);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.isSuccess
              ? 'تم حذف اللمحة'
              : (response.error ?? 'تعذر حذف اللمحة'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: response.isSuccess ? AppColors.success : AppColors.error,
      ),
    );

    if (response.isSuccess) {
      unawaited(_loadMySpotlights());
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  void _openMyQrScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyQrScreen()),
    );
  }

  void _openProviderOrders({String initialTab = 'assigned'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderOrdersScreen(initialTab: initialTab),
      ),
    );
  }

  // ── شريط إحصائيات المزود المضغوط ──
  Widget _buildProviderStatsStrip(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400]! : Colors.grey.shade600;
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.grey.shade200;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _providerStatCell('$_followersCount', 'متابعين', textColor, subColor),
        Container(width: 1, height: 28, color: divColor),
        _providerStatCell('$_followingCount', 'أتابعهم', textColor, subColor),
        Container(width: 1, height: 28, color: divColor),
        _providerStatCell('$_likesReceivedCount', 'إعجابات', textColor, subColor),
      ],
    );
  }

  Widget _statsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFF5E35B1).withValues(alpha: 0.10),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF5E35B1).withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: _buildProviderStatsStrip(isDark),
    );
  }

  Widget _coreKpisCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF0F766E).withValues(alpha: 0.12);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المؤشرات الأساسية',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 12.5 : 13,
              fontWeight: FontWeight.w900,
              color: titleColor,
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Row(
            children: [
              Expanded(
                child: _dashboardKpiTile(
                  icon: Icons.assignment_turned_in_rounded,
                  value: '$_clientsCount',
                  label: 'الطلبات المكتملة',
                  isDark: isDark,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: _dashboardKpiTile(
                  icon: Icons.bookmark_rounded,
                  value: '$_savedByUsersCount',
                  label: 'محفوظ',
                  isDark: isDark,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: _dashboardKpiTile(
                  icon: Icons.qr_code_2_rounded,
                  value: 'QR',
                  label: 'QR نافذتي',
                  isDark: isDark,
                  onTap: _openMyQrScreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboardKpiTile({
    required IconData icon,
    required String value,
    required String label,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    final accent = const Color(0xFF0E7490);
    final background = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFEFFBFA);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : accent.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white60 : const Color(0xFF5A8A92),
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerStatCell(
    String value,
    String label,
    Color textColor,
    Color subColor, {
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 15, color: const Color(0xFF5E35B1))
            else
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF5E35B1),
                  height: 1,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: subColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyManagementSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;
    const accent = Color(0xFF0E7490);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(compact ? 18 : 20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : accent.withValues(alpha: 0.12),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإدارة اليومية',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ادخل مباشرة إلى أكثر الأدوات استخدامًا أثناء العمل.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: compact ? 10 : 10.5,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white60 : const Color(0xFF5A8A92),
              ),
            ),
            const SizedBox(height: 12),
            _managementMenuItem(
              icon: Icons.person_rounded,
              title: 'تعديل الملف الشخصي',
              subtitle: 'اسمك، بياناتك وصورتك',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileTab()),
                );
              },
            ),
            const SizedBox(height: 8),
            _managementMenuItem(
              icon: Icons.home_repair_service_rounded,
              title: 'إدارة الخدمات',
              subtitle: 'خدماتك وأسعارك المقدمة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ServicesTab()),
                );
              },
            ),
            const SizedBox(height: 8),
            _managementMenuItem(
              icon: Icons.reviews_rounded,
              title: 'مراجعات العملاء',
              subtitle: 'تقييماتك وآراء العملاء',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReviewsTab()),
                );
              },
            ),
            const SizedBox(height: 8),
            _managementMenuItem(
              icon: Icons.photo_library_outlined,
              title: 'معرض الأعمال',
              subtitle: 'أبرز مشاريعك وأعمالك',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContentStep(
                      onBack: () => Navigator.pop(context),
                      onNext: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _managementMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF0E7490);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FBFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : accent.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white60 : const Color(0xFF5A8A92),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: isDark ? Colors.white54 : const Color(0xFF5A8A92),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // كرت الباقة — مضغوط + dark mode
  Widget _planCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSubscription = _subscriptionLoaded && _hasSelectedSubscription;
    final isUnsubscribed = _subscriptionLoaded && !_hasSelectedSubscription;
    final statusLabel = hasSubscription ? _currentPlanStatusLabel : null;
    final endAt = hasSubscription ? _subscriptionEndAt : null;
    final expiryLabel = endAt == null ? null : 'ينتهي: ${_formatDate(endAt)}';
    final detail = isUnsubscribed
        ? 'حسابك حاليًا بدون اشتراك فعال، لذلك تعمل أدوات المزود بصلاحيات محدودة حتى التفعيل.'
        : [statusLabel, expiryLabel]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .join(' • ');
    final helper = isUnsubscribed
        ? 'فعّل الباقة الأساسية المجانية الآن لتفتح أدوات الظهور والتوثيق والطلبات المخصصة للمزودين.'
        : null;
    final unsubscribedHighlights = isUnsubscribed
      ? const <String>[
        'الطلبات العاجلة والتنافسية متوقفة حتى تفعيل الاشتراك.',
        'رفع الريلز والأضواء وصور شعار المنصة غير متاح قبل الاشتراك.',
        'رسائل التذكير للعملاء متوقفة حاليًا حتى تفعيل الباقة.',
        'طلب التوثيق يتطلب اشتراكًا فعالًا في الباقة الأساسية أو الأعلى.',
        'ستحتفظ بسعة التخزين المجانية الأساسية، والدعم يتم خلال 5 أيام عمل.',
        ]
      : const <String>[];
    final actionLabel = hasSubscription ? 'إدارة الباقات' : 'تفعيل مجاني';
    final title = isUnsubscribed
        ? 'فعّل باقتك الأساسية المجانية'
        : _currentPlanName;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlansScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.amber.withValues(alpha: 0.12)
              : const Color(0xFFFFFBF0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.amber.withValues(alpha: 0.28)
                : const Color(0xFFFFD54F),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: Color(0xFFF9A825), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: isDark ? Colors.grey[400] : Colors.black54,
                      ),
                    ),
                  if (helper != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      helper,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        height: 1.45,
                        color: isDark ? Colors.grey[300] : Colors.black87,
                      ),
                    ),
                  ],
                  if (unsubscribedHighlights.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...unsubscribedHighlights.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF57F17),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9.8,
                                  height: 1.55,
                                  color:
                                      isDark ? Colors.grey[300] : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF9A825).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: const Color(0xFFF9A825).withValues(alpha: 0.35)),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF57F17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ كرت اكتمال الملف — مضغوط + dark mode
  Widget _profileCompletionCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percent = (_profileCompletion * 100).round();
    const mainColor = Color(0xFF5E35B1);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ProviderProfileCompletionScreen(),
          ),
        );
        if (!mounted) return;
        await _loadProviderData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? mainColor.withValues(alpha: 0.12)
              : const Color(0xFFF5F0FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? mainColor.withValues(alpha: 0.25)
                : mainColor.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'اكتمال الملف',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: mainColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: mainColor.withValues(alpha: 0.8)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: LinearProgressIndicator(
                value: _profileCompletion,
                minHeight: 5,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(mainColor),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: mainColor.withValues(alpha: isDark ? 0.28 : 0.18),
                  ),
                ),
                child: const Text(
                  'أكمل ملفك',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: mainColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickFollowUpSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF5E35B1).withValues(alpha: 0.10);

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF5E35B1).withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المتابعة السريعة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 12.5 : 13,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          _planCard(),
          SizedBox(height: compact ? 8 : 10),
          _profileCompletionCard(),
          SizedBox(height: compact ? 8 : 10),
          _reelsPanel(),
        ],
      ),
    );
  }

  Widget _reelsPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF673AB7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? accent.withValues(alpha: 0.10) : const Color(0xFFF7F2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? accent.withValues(alpha: 0.24)
              : accent.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.video_collection_rounded,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'الريلز والأضواء',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.8,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _reelsRow(embedded: true),
        ],
      ),
    );
  }

  // رأس الصفحة: غلاف + صورة شخصية + اسم
  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 390;
    final isVeryCompact = screenWidth < 360;
    final coverHeight = isVeryCompact ? 158.0 : (isCompact ? 170.0 : 186.0);
    final avatarBottom = isVeryCompact ? -30.0 : (isCompact ? -34.0 : -38.0);
    final nameBottom = isVeryCompact ? -86.0 : (isCompact ? -92.0 : -100.0);
    // ✅ تحديد مصدر صورة الغلاف (محلية أولاً، ثم من API)
    final coverUrl = ApiClient.buildMediaUrl(_resolvedCoverImagePath);
    ImageProvider? coverImageProvider;
    if (_coverImage != null) {
      coverImageProvider = FileImage(_coverImage!);
    } else if (coverUrl != null) {
      coverImageProvider = CachedNetworkImageProvider(coverUrl);
    }

    // ✅ تحديد مصدر الصورة الشخصية (محلية أولاً، ثم من API)
    final profileUrl = ApiClient.buildMediaUrl(_resolvedProfileImagePath);
    ImageProvider? profileImageProvider;
    if (_profileImage != null) {
      profileImageProvider = FileImage(_profileImage!);
    } else if (profileUrl != null) {
      profileImageProvider = CachedNetworkImageProvider(profileUrl);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap:
              _isUploadingProfileMedia ? null : () => _pickImage(isCover: true),
          child: Container(
            height: coverHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: coverImageProvider == null
                  ? LinearGradient(
                      colors: [
                        mainColor,
                        mainColor.withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    )
                  : null,
              image: coverImageProvider != null
                  ? DecorationImage(
                      image: coverImageProvider,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 12,
          right: 12,
          child: SizedBox(height: 64), // placeholder — top bar moved to build()
        ),
        // زر الكاميرا
        Positioned(
          top: 72,
          left: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.photo_camera_outlined,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _isUploadingProfileMedia
                  ? null
                  : () => _pickImage(isCover: true),
            ),
          ),
        ),
        if (_isUploadingProfileMedia)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),

        // صورة شخصية
        Positioned(
          bottom: avatarBottom,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _isUploadingProfileMedia
                  ? null
                  : () => _pickImage(isCover: false),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: isVeryCompact ? 31 : (isCompact ? 33 : 36),
                      backgroundColor: Colors.grey[300],
                      backgroundImage: profileImageProvider,
                      child: profileImageProvider == null
                          ? Icon(
                              Icons.person,
                              color: Colors.white,
                              size: isCompact ? 32 : 36,
                            )
                          : null,
                    ),
                  ),
                  if (_isProviderVerifiedBlue)
                    Positioned(
                      right: 0,
                      bottom: 24,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified,
                          size: 18,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                    ),
                  if (_isProviderVerifiedGreen || _hasProviderExcellenceBadges)
                    Positioned(
                      left: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _hasProviderExcellenceBadges
                              ? Icons.workspace_premium_rounded
                              : Icons.verified_user_rounded,
                          size: 16,
                          color: _hasProviderExcellenceBadges
                              ? const Color(0xFFF9A825)
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 3,
                    right: 3,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: mainColor,
                      child: const Icon(
                        Icons.edit,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: nameBottom,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Text(
                _providerDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isCompact ? 15.5 : 16.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _providerUsernameLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isCompact ? 10.8 : 11.4,
                  color: Colors.grey.shade600,
                ),
              ),
              if (_isProviderVerifiedBlue ||
                  _isProviderVerifiedGreen ||
                  _hasProviderExcellenceBadges) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_isProviderVerifiedBlue)
                      _providerBadgeChip(
                        label: 'توثيق أزرق',
                        icon: Icons.verified,
                        color: const Color(0xFF2196F3),
                      ),
                    if (_isProviderVerifiedGreen)
                      _providerBadgeChip(
                        label: 'توثيق أخضر',
                        icon: Icons.verified_user,
                        color: const Color(0xFF2E7D32),
                      ),
                    if (_hasProviderExcellenceBadges)
                      _providerBadgeChip(
                        label: 'شارات التميز',
                        icon: Icons.workspace_premium_rounded,
                        color: const Color(0xFFF9A825),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _providerBadgeChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: compact ? 9.8 : 10.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// زر التبديل بين حساب العميل وحساب مقدم الخدمة — brand purple + dark mode
  Widget _buildModeToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const mainColor = Color(0xFF5E35B1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1036) : const Color(0xFFF0EAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : mainColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          // Client side (tappable)
          Expanded(
            child: GestureDetector(
              onTap: () async {
                await AccountModeService.setProviderMode(false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم التبديل إلى حساب العميل',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                  Navigator.pushReplacementNamed(context, '/profile');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_rounded,
                        size: 15,
                        color: isDark ? Colors.grey[500]! : Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      'عميل',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                        color: isDark ? Colors.grey[500]! : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Provider side (active)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [mainColor, const Color(0xFF7E57C2)]
                      : [mainColor, const Color(0xFF7E57C2)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: mainColor.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_rounded, size: 15, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'مقدم خدمة',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // إدارة الطلبات
  Widget _ordersCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;
    const purple = AppColors.primary;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: 4),
      child: Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 14,
            compact ? 12 : 14,
            compact ? 12 : 14,
            compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(compact ? 18 : 20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : purple.withValues(alpha: 0.12),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: purple.withValues(alpha: 0.06),
                      blurRadius: compact ? 6 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  children: [
                    Container(
                      width: compact ? 40 : 44,
                      height: compact ? 40 : 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(compact ? 12 : 14),
                        gradient: const LinearGradient(
                          colors: [AppColors.primaryLight, AppColors.primary],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: purple.withValues(alpha: 0.18),
                            blurRadius: compact ? 8 : 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.inventory_2_rounded,
                          color: Colors.white, size: 20),
                  ),
                    SizedBox(width: compact ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "حركة الطلبات",
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF111827),
                              fontSize: compact ? 13.2 : 14,
                              fontWeight: FontWeight.w900,
                              fontFamily: "Cairo",
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "تابع العاجلة والعروض والمسندة بسرعة.",
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF6B7280),
                              fontSize: compact ? 9.8 : 10.4,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              fontFamily: "Cairo",
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    GestureDetector(
                      onTap: () => _openProviderOrders(),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 10,
                          vertical: compact ? 6 : 7,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(compact ? 10 : 12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'فتح',
                              style: TextStyle(
                                color: isDark ? Colors.white : purple,
                                fontSize: compact ? 9.8 : 10.2,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: compact ? 9 : 10,
                              color: isDark ? Colors.white : purple,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
              ),
                SizedBox(height: compact ? 10 : 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ordersMetricBadge(
                      label: 'عاجلة',
                      count: _urgentOrdersCount,
                      accent: AppColors.error,
                      isDark: isDark,
                      onTap: () => _openProviderOrders(initialTab: 'urgent'),
                    ),
                    _ordersMetricBadge(
                      label: 'عروض أسعار',
                      count: _competitiveOrdersCount,
                      accent: AppColors.info,
                      isDark: isDark,
                      onTap: () => _openProviderOrders(initialTab: 'competitive'),
                    ),
                    _ordersMetricBadge(
                      label: 'مسندة',
                      count: _newOrdersCount,
                      accent: Colors.amber.shade700,
                      isDark: isDark,
                      onTap: () => _openProviderOrders(initialTab: 'assigned'),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 12),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(compact ? 12 : 14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: compact ? 14 : 16,
                        color: isDark ? const Color(0xFFD8C7FF) : purple,
                      ),
                      SizedBox(width: compact ? 6 : 8),
                      Expanded(
                        child: Text(
                          'فرز سريع للحالات والطلبات المتاحة.',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : const Color(0xFF5B5670),
                            fontSize: compact ? 9.8 : 10.2,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo',
                          ),
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

  Widget _ordersMetricBadge({
      required String label,
      required int count,
      required Color accent,
      required bool isDark,
      VoidCallback? onTap,
    }) {
      final compact = MediaQuery.sizeOf(context).width < 390;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: compact ? 84 : 92),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(compact ? 13 : 15),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : accent.withValues(alpha: 0.24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  color: isDark ? Colors.white : accent,
                  fontSize: compact ? 15 : 17,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Cairo',
                  height: 1,
                ),
              ),
              SizedBox(height: compact ? 3 : 4),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                  fontSize: compact ? 9.6 : 10.2,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      );
    }

  // لمحات المزود: إضافة + عرض + حذف
  Widget _reelsRow({bool embedded = false}) {
    final spotlights = _mySpotlights;
    final isLocked = _isSpotlightUploadLocked;
    final disabledAccent = Colors.grey.shade400;
    final listPadding = embedded
        ? const EdgeInsets.symmetric(vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 106,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: listPadding,
            itemCount: spotlights.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return GestureDetector(
                  onTap: (isLocked || _isUploadingSpotlight) ? null : _pickVideo,
                  child: Opacity(
                    opacity: isLocked ? 0.68 : 1,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLocked ? disabledAccent : mainColor,
                          width: 2,
                        ),
                        color: Colors.white,
                      ),
                      child: CircleAvatar(
                        radius: 34,
                        backgroundColor:
                            isLocked ? Colors.grey.shade100 : Colors.white,
                        child: _isUploadingSpotlight
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    mainColor,
                                  ),
                                ),
                              )
                            : Icon(
                                isLocked
                                    ? Icons.lock_rounded
                                    : Icons.add,
                                color: isLocked ? disabledAccent : mainColor,
                                size: 24,
                              ),
                      ),
                    ),
                  ),
                );
              }

              final item = spotlights[index - 1];
              final itemId = _toInt(item['id']);
              final rawThumb =
                  ((item['thumbnail_url'] ?? item['file_url']) as String?)
                          ?.trim() ??
                      '';
              final thumbUrl =
                  rawThumb.isEmpty ? null : ApiClient.buildMediaUrl(rawThumb);
              final isDeleting =
                  itemId != null && _deletingSpotlightIds.contains(itemId);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE1BEE7), Color(0xFFFFB74D)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white,
                      backgroundImage: (thumbUrl != null && thumbUrl.isNotEmpty)
                          ? CachedNetworkImageProvider(thumbUrl)
                          : null,
                      child: (thumbUrl == null || thumbUrl.isEmpty)
                          ? const Icon(
                              Icons.play_arrow,
                              color: Colors.deepPurple,
                              size: 26,
                            )
                          : null,
                    ),
                  ),
              Positioned(
                top: -2,
                left: -2,
                child: GestureDetector(
                  onTap: (itemId == null || isDeleting)
                      ? null
                      : () => _deleteSpotlight(itemId),
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: isDeleting ? AppColors.grey400 : AppColors.error,
                    child: isDeleting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.close,
                            color: Colors.white, size: 14),
                  ),
                ),
              ),
                ],
              );
            },
          ),
        ),
        if (isLocked)
          Padding(
            padding: embedded
                ? const EdgeInsetsDirectional.only(top: 2)
                : const EdgeInsetsDirectional.only(start: 16, end: 16, top: 2),
            child: Text(
              'رفع الريلز والأضواء متاح بعد تفعيل إحدى الباقات. الباقة الأساسية المجانية كافية لتفعيل هذه الميزة.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                height: 1.5,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // زر خدمة إضافية (pill)
  Widget _servicePill(
    IconData icon,
    String label,
    Color color, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: "Cairo",
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // الخدمات الإضافية
  Widget _extraServicesSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;
    const purple = Color(0xFF5E35B1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : purple.withValues(alpha: 0.12),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: purple.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
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
                        'التوسع والظهور',
                        style: TextStyle(
                          fontSize: compact ? 14 : 15,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'فعّل خدمات النمو الإضافية وارفع حضورك داخل المنصة بواجهة أوضح ووصول أسرع.',
                        style: TextStyle(
                          fontSize: compact ? 10 : 10.4,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white60 : const Color(0xFF5A8A92),
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : purple.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    'خدمات احترافية',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _servicePill(
                  Icons.campaign,
                  "ترويج",
                  AppColors.success,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PromotionScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _servicePill(
                  Icons.monetization_on,
                  "ترقية",
                  AppColors.warning,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlansScreen()),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _servicePill(
                  Icons.verified,
                  "توثيق",
                  AppColors.info,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VerificationScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                await _openNewAdditionalServicesPage();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF8FBFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : purple.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'عرض كل الخدمات الإضافية',
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: isDark ? Colors.white70 : purple,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ شاشة خطأ
  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadProviderData,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF5E35B1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 390;
    final headerSpacing = compact ? 106.0 : 116.0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0A1E) : const Color(0xFFF5F0FF),
        key: _scaffoldKey,
        drawer: CustomDrawer(),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, compact ? 4 : 6, 12, 0),
                child: PlatformTopBar(
                  overlay: false,
                  height: 62,
                  showMenuButton: true,
                  notificationCount: _notificationUnread,
                  chatCount: _chatUnread,
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                  onNotificationsTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                    _loadUnreadBadges();
                  },
                  onChatsTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyChatsScreen(),
                      ),
                    );
                    _loadUnreadBadges();
                  },
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF5E35B1)),
                    )
            : _errorMessage != null
                ? _buildErrorState(isDark)
                : RefreshIndicator(
                    onRefresh: _loadProviderData,
                    color: mainColor,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: isDark
                            ? const LinearGradient(
                                colors: [Color(0xFF0F0A1E), Color(0xFF130E24), Color(0xFF17112A)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : const LinearGradient(
                                colors: [Color(0xFFF5F0FF), Color(0xFFF7F4FF), Color(0xFFF9F7FF)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                      ),
                      child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          _buildHeader(),
                          SizedBox(height: headerSpacing),
                          // زر التبديل بين الحسابات
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 12 : 14,
                              compact ? 4 : 6,
                              compact ? 12 : 14,
                              compact ? 8 : 10,
                            ),
                            child: _buildModeToggle(),
                          ),
                          // بطاقة رئيسية تحت الغلاف
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
                            child: Column(
                              children: [
                                _statsCard(),
                                SizedBox(height: compact ? 8 : 10),
                                _coreKpisCard(),
                                SizedBox(height: compact ? 8 : 10),
                                _ordersCard(),
                                SizedBox(height: compact ? 8 : 10),
                                _quickFollowUpSection(),
                              ],
                            ),
                          ),
                          _dailyManagementSection(),
                          _extraServicesSection(),
                          const SizedBox(height: 60),
                        ],
                      ),
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
