import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:nawafeth/widgets/bottom_nav.dart';
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
import 'package:nawafeth/screens/additional_services_screen.dart';
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
  final Color mainColor = Colors.deepPurple;

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

    setState(() {
      _userProfile = meResult.data;
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
        backgroundColor: result.isSuccess ? Colors.green : Colors.red,
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
        backgroundColor: result.isSuccess ? Colors.green : Colors.red,
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
              style: TextStyle(fontFamily: 'Cairo', color: Colors.red),
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
        backgroundColor: response.isSuccess ? Colors.green : Colors.red,
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

  // عنصر إحصائية بسيط
  Widget _statItem({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: mainColor),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 11,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // أزرار التنقل الثلاثة
  Widget _dashboardButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black12.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: mainColor),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: "Cairo",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // كرت الباقة (ذهبي بسيط)
  Widget _planCard() {
    final statusLabel = _currentPlanStatusLabel;
    final endAt = _subscriptionEndAt;
    final expiryLabel = endAt == null ? null : 'ينتهي: ${_formatDate(endAt)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Color(0xFFF9A825)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentPlanName,
                  style: const TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (statusLabel != null || expiryLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [statusLabel, expiryLabel]
                          .whereType<String>()
                          .where((item) => item.trim().isNotEmpty)
                          .join(' • '),
                      style: const TextStyle(
                        fontFamily: "Cairo",
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlansScreen()),
              );
            },
            child: const Text(
              "ترقية الباقة",
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 12,
                color: Color(0xFFF57F17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ كرت اكتمال الملف — كامل الكرت ينقل إلى شاشة إكمال الملف التعريفي
  Widget _profileCompletionCard() {
    final percent = (_profileCompletion * 100).round();
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F4FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "اكتمال الملف التعريفي",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  "$percent%",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: mainColor,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: mainColor.withValues(alpha: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: LinearProgressIndicator(
                value: _profileCompletion,
                minHeight: 6,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(mainColor),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "اضغط هنا لإكمال بقية بيانات ملفك التعريفي.",
              style: TextStyle(
                fontSize: 11,
                color: Colors.black54,
                fontFamily: "Cairo",
              ),
            ),
          ],
        ),
      ),
    );
  }

  // رأس الصفحة: غلاف + صورة شخصية + اسم
  Widget _buildHeader() {
    final screenWidth = MediaQuery.of(context).size.width;
    final coverHeight = screenWidth < 380 ? 178.0 : 194.0;
    final avatarBottom = screenWidth < 380 ? -34.0 : -40.0;
    final nameBottom = screenWidth < 380 ? -98.0 : -104.0;
    // ✅ تحديد مصدر صورة الغلاف (محلية أولاً، ثم من API)
    final coverUrl = ApiClient.buildMediaUrl(_resolvedCoverImagePath);
    ImageProvider? coverImageProvider;
    if (_coverImage != null) {
      coverImageProvider = FileImage(_coverImage!);
    } else if (coverUrl != null) {
      coverImageProvider = NetworkImage(coverUrl);
    }

    // ✅ تحديد مصدر الصورة الشخصية (محلية أولاً، ثم من API)
    final profileUrl = ApiClient.buildMediaUrl(_resolvedProfileImagePath);
    ImageProvider? profileImageProvider;
    if (_profileImage != null) {
      profileImageProvider = FileImage(_profileImage!);
    } else if (profileUrl != null) {
      profileImageProvider = NetworkImage(profileUrl);
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
          child: PlatformTopBar(
            overlay: true,
            height: 64,
            notificationCount: _notificationUnread,
            chatCount: _chatUnread,
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
                      radius: screenWidth < 380 ? 36 : 38,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: profileImageProvider,
                      child: profileImageProvider == null
                          ? const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 38,
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
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _providerUsernameLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// زر التبديل بين حساب العميل وحساب مقدم الخدمة (نفس تصميم صفحة العميل)
  Widget _buildModeToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
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
                      backgroundColor: Colors.green,
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
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 5),
                    Text(
                      'عميل',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                        color: Colors.grey.shade500,
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: mainColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_rounded, size: 16, color: mainColor),
                  const SizedBox(width: 5),
                  Text(
                    'مقدم خدمة',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                      color: mainColor,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProviderOrdersScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black12.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.list_alt, color: mainColor),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "إدارة الطلبات",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: "Cairo",
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "$_urgentOrdersCount عاجلة",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: "Cairo",
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        child: Text(
                          "$_competitiveOrdersCount عروض أسعار",
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: "Cairo",
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: Text(
                          "$_newOrdersCount مسندة",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: "Cairo",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // لمحات المزود: إضافة + عرض + حذف
  Widget _reelsRow() {
    final spotlights = _mySpotlights;
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: spotlights.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return GestureDetector(
              onTap: _isUploadingSpotlight ? null : _pickVideo,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: mainColor, width: 2),
                  color: Colors.white,
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white,
                  child: _isUploadingSpotlight
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(mainColor),
                          ),
                        )
                      : Icon(Icons.add, color: mainColor, size: 26),
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
                      ? NetworkImage(thumbUrl)
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
                    backgroundColor: isDeleting ? Colors.grey : Colors.red,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              "خدمات إضافية لتعزيز ظهورك:",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                fontFamily: "Cairo",
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _servicePill(
                  Icons.campaign,
                  "ترويج",
                  Colors.green,
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
                  Colors.orange,
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
                  Colors.blue,
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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdditionalServicesScreen(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "عرض كل الخدمات الإضافية",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: "Cairo",
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ شاشة خطأ
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProviderData,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
            : _errorMessage != null
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: _loadProviderData,
                    color: mainColor,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 118),
                          // زر التبديل بين الحسابات
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                            child: _buildModeToggle(),
                          ),
                          // بطاقة رئيسية تحت الغلاف
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                // الإحصائيات + الباقة + اكتمال الملف
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12.withValues(alpha: 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // ✅ إحصائيات المتابعين والمتابعون — من الـ API
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: () {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text('قائمة المتابعين'),
                                                ),
                                              );
                                            },
                                            child: Column(
                                              children: [
                                                const Icon(
                                                  Icons.groups_rounded,
                                                  size: 18,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '$_followersCount',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                const Text(
                                                  'متابع',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 40),
                                          GestureDetector(
                                            onTap: () {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text('قائمة المتابَعون'),
                                                ),
                                              );
                                            },
                                            child: Column(
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .person_add_alt_1_rounded,
                                                  size: 18,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '$_followingCount',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                const Text(
                                                  'يتابع',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          _statItem(
                                            icon: Icons.thumb_up_alt_outlined,
                                            label: "إعجابات",
                                            value: '$_likesReceivedCount',
                                          ),
                                          const SizedBox(width: 6),
                                          _statItem(
                                            icon: Icons.person_outline,
                                            label: "الطلبات المكتملة",
                                            value: '$_clientsCount',
                                          ),
                                          const SizedBox(width: 6),
                                          _statItem(
                                            icon: Icons.bookmark_border,
                                            label: "محفوظ",
                                            value: '$_savedByUsersCount',
                                          ),
                                          const SizedBox(width: 6),
                                          _statItem(
                                            icon: Icons.qr_code,
                                            label: "QR نافذتي",
                                            value: "",
                                            onTap: _openMyQrScreen,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _planCard(),
                                      const SizedBox(height: 10),
                                      _profileCompletionCard(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _ordersCard(),
                              ],
                            ),
                          ),
                          _reelsRow(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    _dashboardButton(
                                        Icons.person, "الملف الشخصي", () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const ProfileTab(),
                                        ),
                                      );
                                    }),
                                    _dashboardButton(
                                      Icons.home_repair_service,
                                      "خدماتي",
                                      () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const ServicesTab(),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _dashboardButton(Icons.reviews, "المراجعات",
                                        () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const ReviewsTab(),
                                        ),
                                      );
                                    }),
                                    _dashboardButton(
                                      Icons.photo_library_outlined,
                                      "معرض الأعمال",
                                      () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ContentStep(
                                              onBack: () =>
                                                  Navigator.pop(context),
                                              onNext: () =>
                                                  Navigator.pop(context),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _extraServicesSection(),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
