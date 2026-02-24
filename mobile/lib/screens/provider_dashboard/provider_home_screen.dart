
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/account_api.dart';
import '../../services/api_config.dart';
import '../../services/providers_api.dart';
import '../../services/reviews_api.dart';
import '../../services/account_switcher.dart';
import '../../services/marketplace_api.dart';
import '../../services/subscriptions_api.dart';
import '../../services/verification_api.dart';
import '../../services/extras_api.dart';
import '../../services/promo_api.dart';
import '../../constants/colors.dart';
import '../../models/provider_portfolio_item.dart';

import '../../widgets/bottom_nav.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/profile_account_modes_panel.dart';
import '../../widgets/account_switch_sheet.dart';
import '../../widgets/profile_quick_links_panel.dart';

import 'services_tab.dart';
import 'reviews_tab.dart'; 
import 'provider_completion_utils.dart';
import 'provider_orders_screen.dart';
import 'provider_profile_completion_screen.dart';
import 'provider_portfolio_manage_screen.dart';
import 'paid_services_hub_screen.dart';
import '../verification_screen.dart';
import '../plans_screen.dart';
import '../extra_services_screen.dart';
import '../promo_requests_screen.dart';
import '../../screens/network_video_player_screen.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen>
    with SingleTickerProviderStateMixin {
  
  final Color providerPrimary = AppColors.deepPurple;
  final Color providerAccent = AppColors.primaryDark;
  
  File? _profileImage;
  File? _coverImage;
  String? _profileImageUrl;
  String? _coverImageUrl;
  
  bool _isLoading = true;
  String? _providerDisplayName;
  String? _providerUsername;
  String? _providerShareLink;
  int? _followersCount;
  int? _likesReceivedCount;
  int? _providerId;
  double _profileCompletion = 0.0;
  String _profileBio = '';
  String _profileAboutDetails = '';
  String _accountFirstName = '';
  String _accountLastName = '';

  double _ratingAvg = 0.0;
  int _ratingCount = 0;
  bool _switchingAccount = false;
  int _completedOrdersCount = 0;

  bool _loadingSpotlights = false;
  bool _savingSpotlight = false;
  List<ProviderPortfolioItem> _mySpotlights = const [];
  int _paidServicesPendingCount = 0;
  bool _loadingPaidServicesBadge = false;
  int _pendingVerificationCount = 0;
  int _pendingSubscriptionsCount = 0;
  int _pendingExtrasCount = 0;
  int _pendingPromoCount = 0;
  int _rejectedVerificationCount = 0;
  int _rejectedSubscriptionsCount = 0;
  int _rejectedExtrasCount = 0;
  int _rejectedPromoCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProviderData();
  }

  Future<void> _loadProviderData() async {
    try {
      final me = await AccountApi().me();
      final id = me['provider_profile_id'];
      final int? providerId = id is int ? id : int.tryParse((id ?? '').toString());

      int? asInt(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse((v ?? '').toString());
      }

      final followersCount = asInt(me['provider_followers_count']);
      final likesReceivedCount = asInt(me['provider_likes_received_count']);

      Map<String, dynamic>? myProfile;
      try {
        myProfile = await ProvidersApi().getMyProviderProfile();
      } catch (_) {}
      List<int> subcategoryIds = <int>[];
      try {
        subcategoryIds = await ProvidersApi().getMyProviderSubcategories();
      } catch (_) {
        subcategoryIds = <int>[];
      }

      final providerDisplayName = (myProfile?['display_name'] ?? '').toString().trim();
      final providerUsername = (me['username'] ?? '').toString().trim();
      final profileImageUrl = _normalizeMediaUrl(myProfile?['profile_image']);
      final coverImageUrl = _normalizeMediaUrl(myProfile?['cover_image']);
      final profileBio = (myProfile?['bio'] ?? '').toString().trim();
      final profileAboutDetails = (myProfile?['about_details'] ?? '').toString().trim();
      final accountFirstName = (me['first_name'] ?? '').toString().trim();
      final accountLastName = (me['last_name'] ?? '').toString().trim();

      // --- Profile Completion Logic (backend-driven) ---
      final sectionDone = ProviderCompletionUtils.deriveSectionDone(
        providerProfile: myProfile,
        subcategories: subcategoryIds,
      );
      final completionPercent = ProviderCompletionUtils.completionPercent(
        me: me,
        sectionDone: sectionDone,
      );
      // ----------------------------------------

      String? link;
      if (providerId != null) {
        link = '${ApiConfig.baseUrl}${ApiConfig.apiPrefix}/providers/$providerId/';
      }

      // --- Provider Rating (real, non-dummy) ---
      double ratingAvg = 0.0;
      int ratingCount = 0;
      if (providerId != null) {
        try {
          final rating = await ReviewsApi().getProviderRatingSummary(providerId);
          final avg = rating['rating_avg'] ?? 0;
          final count = rating['rating_count'] ?? 0;

        double asDouble(dynamic v) {
          if (v is double) return v;
          if (v is int) return v.toDouble();
          if (v is num) return v.toDouble();
          return double.tryParse((v ?? '').toString()) ?? 0.0;
        }

        int asIntSafe(dynamic v) {
          if (v is int) return v;
          if (v is num) return v.toInt();
          return int.tryParse((v ?? '').toString()) ?? 0;
        }

          ratingAvg = asDouble(avg);
          ratingCount = asIntSafe(count);
          if (ratingCount <= 0) {
            ratingAvg = 0.0;
            ratingCount = 0;
          }
        } catch (_) {
          // ignore: keep defaults
        }
      }

      if (!mounted) return;
      setState(() {
        _providerId = providerId;
        _providerShareLink = link;
        _followersCount = followersCount;
        _likesReceivedCount = likesReceivedCount;
        _providerDisplayName = providerDisplayName.isEmpty ? null : providerDisplayName;
        _providerUsername = providerUsername.isEmpty ? null : providerUsername;
        _profileImageUrl = profileImageUrl;
        _coverImageUrl = coverImageUrl;
        _profileBio = profileBio;
        _profileAboutDetails = profileAboutDetails;
        _accountFirstName = accountFirstName;
        _accountLastName = accountLastName;
        _profileCompletion = completionPercent;
        _ratingAvg = ratingAvg;
        _ratingCount = ratingCount;
        _isLoading = false;
      });
      _loadPaidServicesBadge();
      await _loadCompletedOrdersCount();
      await _loadMySpotlights();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _normalizeMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '${ApiConfig.baseUrl}$value';
    }
    return value;
  }

  ImageProvider<Object>? _avatarImageProvider() {
    if (_profileImage != null) return FileImage(_profileImage!);
    if ((_profileImageUrl ?? '').trim().isNotEmpty) {
      return NetworkImage(_profileImageUrl!);
    }
    return null;
  }

  Future<void> _loadCompletedOrdersCount() async {
    try {
      final list = await MarketplaceApi().getMyProviderRequests(statusGroup: 'completed');
      if (!mounted) return;
      setState(() => _completedOrdersCount = list.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _completedOrdersCount = 0);
    }
  }

  Future<void> _loadPaidServicesBadge() async {
    if (!mounted) return;
    setState(() => _loadingPaidServicesBadge = true);
    try {
      List<Map<String, dynamic>> verification = const [];
      List<Map<String, dynamic>> subscriptions = const [];
      List<Map<String, dynamic>> extras = const [];
      List<Map<String, dynamic>> promo = const [];

      await Future.wait([
        () async {
          try {
            verification = await VerificationApi().getMyRequests();
          } catch (_) {}
        }(),
        () async {
          try {
            subscriptions = await SubscriptionsApi().getMySubscriptions();
          } catch (_) {}
        }(),
        () async {
          try {
            extras = await ExtrasApi().getMyExtras();
          } catch (_) {}
        }(),
        () async {
          try {
            promo = await PromoApi().getMyRequests();
          } catch (_) {}
        }(),
      ]);

      final verificationPending = _countPendingLike(verification);
      final subscriptionsPending = _countPendingLike(subscriptions);
      final extrasPending = _countPendingLike(extras);
      final promoPending = _countPendingLike(promo);
      final verificationRejected = _countRejectedLike(verification);
      final subscriptionsRejected = _countRejectedLike(subscriptions);
      final extrasRejected = _countRejectedLike(extras);
      final promoRejected = _countRejectedLike(promo);
      final totalPending = verificationPending + subscriptionsPending + extrasPending + promoPending;

      if (!mounted) return;
      setState(() {
        _paidServicesPendingCount = totalPending;
        _pendingVerificationCount = verificationPending;
        _pendingSubscriptionsCount = subscriptionsPending;
        _pendingExtrasCount = extrasPending;
        _pendingPromoCount = promoPending;
        _rejectedVerificationCount = verificationRejected;
        _rejectedSubscriptionsCount = subscriptionsRejected;
        _rejectedExtrasCount = extrasRejected;
        _rejectedPromoCount = promoRejected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paidServicesPendingCount = 0;
        _pendingVerificationCount = 0;
        _pendingSubscriptionsCount = 0;
        _pendingExtrasCount = 0;
        _pendingPromoCount = 0;
        _rejectedVerificationCount = 0;
        _rejectedSubscriptionsCount = 0;
        _rejectedExtrasCount = 0;
        _rejectedPromoCount = 0;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingPaidServicesBadge = false);
      }
    }
  }

  int _countPendingLike(List<Map<String, dynamic>> rows) {
    const pendingStatuses = <String>{
      'pending',
      'submitted',
      'processing',
      'awaiting_payment',
      'awaiting-review',
      'awaiting_review',
      'unpaid',
      'created',
      'new',
    };
    var count = 0;
    for (final row in rows) {
      final raw = (row['status'] ?? row['state'] ?? row['payment_status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (raw.isEmpty) continue;
      if (pendingStatuses.contains(raw)) {
        count++;
      }
    }
    return count;
  }

  int _countRejectedLike(List<Map<String, dynamic>> rows) {
    const rejectedStatuses = <String>{
      'rejected',
      'declined',
      'failed',
      'cancelled',
      'canceled',
      'expired',
      'void',
    };
    var count = 0;
    for (final row in rows) {
      final raw = (row['status'] ?? row['state'] ?? row['payment_status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (raw.isEmpty) continue;
      if (rejectedStatuses.contains(raw)) {
        count++;
      }
    }
    return count;
  }

  Future<void> _showPaidServicesBadgeBreakdown() async {
    if (!mounted) return;
    final total = _pendingVerificationCount +
        _pendingSubscriptionsCount +
        _pendingExtrasCount +
        _pendingPromoCount;
    final totalRejected = _rejectedVerificationCount +
        _rejectedSubscriptionsCount +
        _rejectedExtrasCount +
        _rejectedPromoCount;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget item({
          required IconData icon,
          required String title,
          required int count,
          required int rejectedCount,
          required VoidCallback onTap,
        }) {
          final hasRejected = rejectedCount > 0;
          final hasPending = count > 0;
          final accent = hasRejected
              ? Colors.red
              : (hasPending ? Colors.orange : Colors.green);
          final bg = hasRejected
              ? Colors.red.withValues(alpha: 0.08)
              : (hasPending
                  ? Colors.orange.withValues(alpha: 0.08)
                  : Colors.green.withValues(alpha: 0.08));
          final stateLabel = hasRejected
              ? 'مرفوض ($rejectedCount)'
              : (hasPending ? 'معلّق' : 'سليم');
          return ListTile(
            onTap: () {
              Navigator.pop(sheetContext);
              onTap();
            },
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent.shade700, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              stateLabel,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: accent.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasRejected
                    ? Colors.red.withValues(alpha: 0.12)
                    : (hasPending
                        ? Colors.orange.withValues(alpha: 0.12)
                        : Colors.green.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  color: hasRejected
                      ? Colors.red.shade800
                      : (hasPending ? Colors.orange.shade800 : Colors.green.shade800),
                ),
              ),
            ),
          );
        }

        final totalAccent = totalRejected > 0
            ? Colors.red
            : (total > 0 ? Colors.orange : Colors.green);
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'تفصيل الخدمات المدفوعة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.deepPurple,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: totalRejected > 0
                              ? Colors.red.withValues(alpha: 0.12)
                              : (total > 0
                                  ? Colors.orange.withValues(alpha: 0.12)
                                  : Colors.green.withValues(alpha: 0.12)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          totalRejected > 0
                              ? 'مرفوض: $totalRejected | معلّق: $total'
                              : (total > 0 ? 'المعلّق: $total' : 'لا يوجد معلّق'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: totalAccent.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اضغط على أي قسم للانتقال المباشر إليه.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  item(
                    icon: Icons.verified_outlined,
                    title: 'التوثيق',
                    count: _pendingVerificationCount,
                    rejectedCount: _rejectedVerificationCount,
                    onTap: _openVerificationSection,
                  ),
                  item(
                    icon: Icons.arrow_circle_up_outlined,
                    title: 'الترقية / الاشتراكات',
                    count: _pendingSubscriptionsCount,
                    rejectedCount: _rejectedSubscriptionsCount,
                    onTap: _openPlansSection,
                  ),
                  item(
                    icon: Icons.add_box_outlined,
                    title: 'الخدمات الإضافية',
                    count: _pendingExtrasCount,
                    rejectedCount: _rejectedExtrasCount,
                    onTap: _openExtrasSection,
                  ),
                  item(
                    icon: Icons.campaign_outlined,
                    title: 'الترويج',
                    count: _pendingPromoCount,
                    rejectedCount: _rejectedPromoCount,
                    onTap: _openPromoSection,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _openPaidServicesHub();
                      },
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text(
                        'فتح مركز الخدمات المدفوعة',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.deepPurple,
                        side: BorderSide(color: AppColors.deepPurple.withValues(alpha: 0.25)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPaidServicesHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaidServicesHubScreen()),
    );
    if (!mounted) return;
    await _loadPaidServicesBadge();
  }

  Future<void> _openVerificationSection() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerificationScreen()),
    );
    if (!mounted) return;
    await _loadPaidServicesBadge();
  }

  Future<void> _openPlansSection() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlansScreen()),
    );
    if (!mounted) return;
    await _loadPaidServicesBadge();
  }

  Future<void> _openExtrasSection() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExtraServicesScreen()),
    );
    if (!mounted) return;
    await _loadPaidServicesBadge();
  }

  Future<void> _openPromoSection() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PromoRequestsScreen()),
    );
    if (!mounted) return;
    await _loadPaidServicesBadge();
  }

  Future<void> _loadMySpotlights() async {
    if (!mounted) return;
    setState(() => _loadingSpotlights = true);
    try {
      final items = await ProvidersApi().getMySpotlights();
      if (!mounted) return;
      setState(() {
        _mySpotlights = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mySpotlights = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingSpotlights = false);
    }
  }

  String _detectFileType(String name) {
    final lower = name.toLowerCase();
    const videoExt = [
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.webm',
      '.m4v',
    ];
    for (final ext in videoExt) {
      if (lower.endsWith(ext)) return 'video';
    }
    return 'image';
  }

  Future<void> _createSpotlightFromFile(PlatformFile file) async {
    if (_savingSpotlight) return;
    final fileType = _detectFileType(file.name);
    setState(() => _savingSpotlight = true);
    try {
      final created = await ProvidersApi().createMySpotlightItem(
        file: file,
        fileType: fileType,
      );
      if (!mounted) return;
      if (created == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ اللمحة')),
        );
        return;
      }
      await _loadMySpotlights();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ اللمحة بنجاح')),
      );
    } finally {
      if (mounted) setState(() => _savingSpotlight = false);
    }
  }

  Future<void> _pickSpotlightImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final file = PlatformFile(
      name: picked.name,
      size: await File(picked.path).length(),
      path: picked.path,
    );
    await _createSpotlightFromFile(file);
  }

  Future<void> _pickSpotlightFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final file = PlatformFile(
      name: picked.name,
      size: await File(picked.path).length(),
      path: picked.path,
    );
    await _createSpotlightFromFile(file);
  }

  Future<void> _pickSpotlightFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'png', 'jpg', 'jpeg', 'webp',
        'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    await _createSpotlightFromFile(result.files.first);
  }

  Future<void> _showCreateSpotlightDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.deepPurple, width: 1.2),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.video_collection_outlined, color: AppColors.deepPurple),
                    SizedBox(width: 8),
                    Text(
                      'إضافة لمحة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickSpotlightImageFromGallery();
                  },
                  title: const Text('Photo Library', style: TextStyle(fontFamily: 'Cairo')),
                  trailing: const Icon(Icons.photo_library_outlined),
                ),
                ListTile(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickSpotlightFromCamera();
                  },
                  title: const Text('Take Photo', style: TextStyle(fontFamily: 'Cairo')),
                  trailing: const Icon(Icons.camera_alt_outlined),
                ),
                ListTile(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickSpotlightFile();
                  },
                  title: const Text('Choose File', style: TextStyle(fontFamily: 'Cairo')),
                  trailing: const Icon(Icons.folder_open_outlined),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: AppColors.deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSpotlight(ProviderPortfolioItem item) async {
    final ok = await ProvidersApi().deleteMySpotlightItem(item.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف اللمحة')),
      );
      return;
    }
    await _loadMySpotlights();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف اللمحة')),
    );
  }

  Future<void> _pickImage({required bool isCover, ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        isCover ? _coverImage = File(picked.path) : _profileImage = File(picked.path);
      });

      final updated = await ProvidersApi().uploadMyProviderImages(
        profileImagePath: isCover ? null : picked.path,
        coverImagePath: isCover ? picked.path : null,
      );
      if (!mounted) return;
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم التحديث محليًا فقط، تعذر حفظ الصورة في الخادم')),
        );
        return;
      }
      setState(() {
        if (isCover) {
          _coverImageUrl = _normalizeMediaUrl(updated['cover_image']);
        } else {
          _profileImageUrl = _normalizeMediaUrl(updated['profile_image']);
        }
      });
    }
  }

  Future<void> _showCoverEditSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تعديل خلفية الهيدر',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('اختيار من المعرض', style: TextStyle(fontFamily: 'Cairo')),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImage(isCover: true, source: ImageSource.gallery);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.camera_alt_outlined),
                    title: const Text('التقاط صورة', style: TextStyle(fontFamily: 'Cairo')),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImage(isCover: true, source: ImageSource.camera);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQrDialog() {
    final rootContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('QR ملف المزود', style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: providerPrimary)),
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                height: 200,
                child: _providerShareLink == null 
                  ? const Center(child: Text('الرابط غير متوفر'))
                  : QrImageView(data: _providerShareLink!, padding: EdgeInsets.zero,),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _providerShareLink == null ? null : () async {
                         final messenger = ScaffoldMessenger.of(rootContext);
                         Navigator.pop(dialogContext);
                         await Clipboard.setData(ClipboardData(text: _providerShareLink!));
                         if (!mounted) return;
                         messenger.showSnackBar(const SnackBar(content: Text('تم نسخ الرابط')));
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ الرابط', style: TextStyle(fontFamily: 'Cairo')),
                      style: ElevatedButton.styleFrom(backgroundColor: providerPrimary, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _providerShareLink == null ? null : () async {
                        await Share.share(_providerShareLink!);
                      },
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('مشاركة', style: TextStyle(fontFamily: 'Cairo')),
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
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: providerPrimary)),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.primaryLight,
        drawer: const CustomDrawer(),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 280.0,
                floating: false,
                pinned: true,
                backgroundColor: providerPrimary,
                leading: Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    onPressed: () => Navigator.pushNamed(context, '/notifications'),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              providerPrimary,
                              providerAccent,
                              AppColors.primaryDark,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      if (_coverImage != null)
                        Image.file(_coverImage!, fit: BoxFit.cover)
                      else if ((_coverImageUrl ?? '').trim().isNotEmpty)
                        Image.network(
                          _coverImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 54),
                            Stack(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    color: Colors.white24,
                                  ),
                                  child: CircleAvatar(
                                    radius: 46,
                                    backgroundColor: Colors.white,
                                    backgroundImage: _avatarImageProvider(),
                                    child: _profileImage == null ? Icon(Icons.storefront, size: 40, color: providerPrimary) : null,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () => _pickImage(isCover: false),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _providerDisplayName ?? 'مزود خدمة محترف',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_providerUsername != null)
                              Text(
                                '@$_providerUsername',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 76,
                        left: 16,
                        child: GestureDetector(
                          onTap: _showCoverEditSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.edit, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'تعديل',
                                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(30),
                  child: Container(
                    height: 30,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: RefreshIndicator(
            color: AppColors.deepPurple,
            onRefresh: _loadProviderData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildSpotlightsSection(),
                    const SizedBox(height: 16),
                    _buildCompletionCard(),
                    const SizedBox(height: 14),
                    _buildAccountModesSection(),
                    const SizedBox(height: 18),
                    _buildQuickLinks(),
                    const SizedBox(height: 36),
                  ],
                ),
            ),
          ),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      ),
    );
  }

  Widget _buildAccountModesSection() {
    return ProfileAccountModesPanel(
      isProviderRegistered: true,
      isProviderActive: true,
      isSwitching: _switchingAccount,
      onSelectMode: _onSelectMode,
    );
  }

  Widget _buildTopMetricsRow() {
    final ratingText = _ratingAvg.toStringAsFixed(1);
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _showQrDialog,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.qr_code_2_rounded, color: AppColors.deepPurple, size: 18),
                SizedBox(width: 4),
                Text(
                  'QR',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          ratingText,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: AppColors.deepPurple,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.star_rounded, color: Colors.amber, size: 21),
        const SizedBox(width: 4),
        Text(
          '($_ratingCount)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppColors.deepPurple.withValues(alpha: 0.8),
          ),
        ),
        const Spacer(),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.deepPurple.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.deepPurple),
        ),
        const SizedBox(width: 8),
        _miniCounter(icon: Icons.bookmark_border_rounded, value: _mySpotlights.length.toString()),
        const SizedBox(width: 8),
        _miniCounter(icon: Icons.person_add_alt_1_rounded, value: (_followersCount ?? 0).toString()),
        const SizedBox(width: 8),
        _miniCounter(icon: Icons.thumb_up_alt_outlined, value: (_likesReceivedCount ?? 0).toString()),
      ],
    );
  }

  Widget _miniCounter({
    required IconData icon,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppColors.deepPurple, size: 18),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Cairo',
            color: AppColors.deepPurple,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionCard() {
    final percent = (_profileCompletion * 100).round();
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProviderProfileCompletionScreen()),
        );
        await _loadProviderData();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.deepPurple]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
             BoxShadow(color: AppColors.deepPurple.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _profileCompletion,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  strokeWidth: 4,
                ),
                Text('$percent%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الملف التعريفي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('زيادة اكتمال الملف تزيد من ظهورك في البحث', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotlightsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopMetricsRow(),
          const SizedBox(height: 10),
          Row(
            children: [
              _completedOrdersIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _navToOrders,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text(
                    'إدارة الطلبات',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _savingSpotlight ? null : _showCreateSpotlightDialog,
                  icon: _savingSpotlight
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.video_call_rounded),
                  label: const SizedBox.shrink(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTopShortcutRow(),
          const SizedBox(height: 10),
          const Text(
            'اللمحات السابقة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              color: AppColors.deepPurple,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingSpotlights)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(color: AppColors.deepPurple),
              ),
            )
          else if (_mySpotlights.isEmpty)
            SizedBox(
              height: 86,
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.deepPurple.withValues(alpha: 0.45),
                          width: 1.6,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          color: AppColors.deepPurple,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _mySpotlights.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = _mySpotlights[index];
                  return _buildSpotlightItem(item);
                },
              ),
            ),
          const SizedBox(height: 12),
          _buildProviderInfoEditorCard(),
        ],
      ),
    );
  }

  Widget _buildProviderInfoEditorCard() {
    final fullName = '${_accountFirstName.trim()} ${_accountLastName.trim()}'.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDark.withValues(alpha: 0.24)),
      ),
      child: Column(
        children: [
          _editableInfoRow(
            title: 'الاسم الكامل للحساب',
            value: fullName.isEmpty ? 'غير مضاف' : fullName,
            onEdit: _editAccountFullName,
          ),
          const SizedBox(height: 8),
          _editableInfoRow(
            title: 'اسم المستخدم',
            value: (_providerUsername ?? '').trim().isEmpty ? 'غير مضاف' : '@${_providerUsername!.trim()}',
            onEdit: null,
          ),
          const SizedBox(height: 8),
          _editableInfoRow(
            title: 'صفة الحساب',
            value: _profileBio.isEmpty ? 'غير مضاف' : _profileBio,
            onEdit: _editBio,
          ),
          const SizedBox(height: 8),
          _editableInfoRow(
            title: 'نبذة عنك (منشأتك) كمقدم خدمة',
            value: _profileAboutDetails.isEmpty ? 'غير مضاف' : _profileAboutDetails,
            maxLines: 3,
            onEdit: _editAboutDetails,
          ),
        ],
      ),
    );
  }

  Widget _editableInfoRow({
    required String title,
    required String value,
    VoidCallback? onEdit,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.deepPurple,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.grey[800],
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onEdit != null)
          OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepPurple,
              side: BorderSide(color: AppColors.deepPurple.withValues(alpha: 0.35)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(68, 30),
            ),
            child: const Text(
              'تعديل',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildTopShortcutRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 24) / 4;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: itemWidth,
              child: _circleShortcut(
                icon: Icons.person_outline_rounded,
                label: 'الملف الشخصي',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProviderProfileCompletionScreen()),
                  ).then((_) => _loadProviderData());
                },
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _circleShortcut(
                icon: Icons.design_services_outlined,
                label: 'خدماتي',
                onTap: _navToServices,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _circleShortcut(
                icon: Icons.photo_library_outlined,
                label: 'معرض الخدمات',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProviderPortfolioManageScreen()),
                  );
                  await _loadMySpotlights();
                },
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _circleShortcut(
                icon: Icons.rate_review_outlined,
                label: 'المراجعات',
                onTap: _navToReviews,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _completedOrdersIcon() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.deepPurple.withValues(alpha: 0.60),
          width: 1.4,
        ),
        color: AppColors.primaryLight,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Center(
            child: Icon(
              Icons.assignment_outlined,
              color: AppColors.deepPurple,
              size: 24,
            ),
          ),
          Positioned(
            top: -5,
            left: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.deepPurple,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                _completedOrdersCount.toString(),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleShortcut({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.70), width: 2),
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryLight,
                border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.26)),
              ),
              child: Icon(icon, color: AppColors.deepPurple, size: 26),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSimpleEditDialog({
    required String title,
    required String initialValue,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<void> _editAccountFullName() async {
    final current = '${_accountFirstName.trim()} ${_accountLastName.trim()}'.trim();
    final value = await _showSimpleEditDialog(
      title: 'تعديل الاسم الكامل',
      initialValue: current,
    );
    if (value == null) return;
    final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    try {
      await AccountApi().updateMe({
        'first_name': first,
        'last_name': last,
      });
      await _loadProviderData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث الاسم')),
      );
    }
  }

  Future<void> _editBio() async {
    final value = await _showSimpleEditDialog(
      title: 'تعديل صفة الحساب',
      initialValue: _profileBio,
      minLines: 2,
      maxLines: 3,
    );
    if (value == null) return;
    try {
      await ProvidersApi().updateMyProviderProfile({'bio': value});
      await _loadProviderData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث صفة الحساب')),
      );
    }
  }

  Future<void> _editAboutDetails() async {
    final value = await _showSimpleEditDialog(
      title: 'تعديل النبذة',
      initialValue: _profileAboutDetails,
      minLines: 3,
      maxLines: 5,
    );
    if (value == null) return;
    try {
      await ProvidersApi().updateMyProviderProfile({'about_details': value});
      await _loadProviderData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث النبذة')),
      );
    }
  }

  Widget _buildSpotlightItem(ProviderPortfolioItem item) {
    final isVideo = item.fileType.toLowerCase().contains('video');
    return SizedBox(
      width: 82,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => _openSpotlight(item),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.deepPurple.withValues(alpha: 0.7),
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                item.fileUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: AppColors.primaryLight,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.deepPurple,
                                  ),
                                ),
                              ),
                              if (isVideo)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: InkWell(
                    onTap: () => _confirmDeleteSpotlight(item),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.caption.trim().isEmpty ? 'لمحة' : item.caption.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: AppColors.deepPurple,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSpotlight(ProviderPortfolioItem item) async {
    if (item.fileType.toLowerCase().contains('video')) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NetworkVideoPlayerScreen(
            url: item.fileUrl,
            title: item.caption.trim().isEmpty ? 'لمحة فيديو' : item.caption.trim(),
          ),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 30),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Image.network(
                  item.fileUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 52),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSpotlight(ProviderPortfolioItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'حذف اللمحة',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'هل تريد حذف هذه اللمحة؟',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteSpotlight(item);
    }
  }

  Widget _buildQuickLinks() {
    final totalRejected = _rejectedVerificationCount +
        _rejectedSubscriptionsCount +
        _rejectedExtrasCount +
        _rejectedPromoCount;
    final badgeCount = _paidServicesPendingCount + totalRejected;
    final hasRejected = totalRejected > 0;

    return ProfileQuickLinksPanel(
      title: 'إعدادات سريعة',
      items: [
        ProfileQuickLinkItem(
          title: 'الخدمات المدفوعة (توثيق / ترقية / ترويج / إضافات)',
          icon: Icons.workspace_premium_outlined,
          badgeText: _loadingPaidServicesBadge
              ? '...'
              : (badgeCount > 0 ? badgeCount.toString() : null),
          badgeBackgroundColor: hasRejected
              ? Colors.red.withValues(alpha: 0.12)
              : (_paidServicesPendingCount > 0
                  ? Colors.orange.withValues(alpha: 0.12)
                  : AppColors.deepPurple.withValues(alpha: 0.10)),
          badgeTextColor: hasRejected
              ? Colors.red.shade800
              : (_paidServicesPendingCount > 0
                  ? Colors.orange.shade800
                  : AppColors.deepPurple),
          onLongPress: _showPaidServicesBadgeBreakdown,
          onTap: () {
            _openPaidServicesHub();
          },
        ),
      ],
    );
  }

  void _navToServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ServicesTab(),
      ),
    );
  }

  void _navToOrders() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderOrdersScreen()));
  }

  Future<void> _navToReviews() async {
     await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('التقييمات', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: providerPrimary, foregroundColor: Colors.white,),
      body: ReviewsTab(
        embedded: true,
        providerId: _providerId,
        allowProviderReply: true,
      ),
    )));
    if (!mounted) return;
    await _loadProviderData();
  }

  Future<void> _onSelectMode(AccountMode mode) async {
    if (_switchingAccount) return;
    setState(() => _switchingAccount = true);
    try {
      await AccountSwitcher.switchTo(context, mode);
    } finally {
      if (mounted) {
        setState(() => _switchingAccount = false);
      }
    }
  }
}
