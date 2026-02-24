import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/app_bar.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/platform_report_dialog.dart';
import 'provider_dashboard/reviews_tab.dart';
import 'network_video_player_screen.dart';
import 'service_request_form_screen.dart';
import '../services/providers_api.dart'; // Added
import '../services/api_config.dart';
import '../models/provider.dart'; // Added
import '../models/provider_portfolio_item.dart';
import '../models/provider_service.dart';
import '../models/user_summary.dart';
import '../services/chat_nav.dart';
import '../services/messaging_api.dart';
import '../services/account_api.dart';
import '../services/support_api.dart';
import '../utils/auth_guard.dart'; // Added
import '../utils/whatsapp_helper.dart';

import 'provider_dashboard/provider_portfolio_manage_screen.dart';

class ProviderProfileScreen extends StatefulWidget {
  final String? providerId;
  final String? providerName;
  final String? providerCategory;
  final String? providerSubCategory;
  final double? providerRating;
  final int? providerOperations;
  final String? providerImage;
  final bool? providerVerified;
  final String? providerPhone;
  final double? providerLat;
  final double? providerLng;

  const ProviderProfileScreen({
    super.key,
    this.providerId,
    this.providerName,
    this.providerCategory,
    this.providerSubCategory,
    this.providerRating,
    this.providerOperations,
    this.providerImage,
    this.providerVerified,
    this.providerPhone,
    this.providerLat,
    this.providerLng,
  });

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final Color mainColor = Colors.deepPurple;

  bool _canManageGallery = false;

  int _selectedTabIndex = 0;

  bool _isFollowingProvider = false;
  bool _isFollowBusy = false;

  bool _isProviderLiked = false;
  bool _isLikeBusy = false;

  Set<int> _favoritePortfolioIds = <int>{};
  final Set<int> _portfolioFavoriteBusyIds = <int>{};
  final Set<int> _favoriteHighlightIndexes = <int>{};

  // عدادات أعلى الصفحة (من API العام لمقدم الخدمة)
  int? _completedRequests;
  int? _followersCount;
  int? _followingCount;
  int? _likesCount;

  int? _reviewersCount;
  double? _ratingAvgOverride;

  final List<Map<String, dynamic>> tabs = const [
    {"title": "الملف الشخصي", "icon": Icons.person_outline},
    {"title": "التصنيفات", "icon": Icons.work_outline},
    {"title": "معرض خدماتي", "icon": Icons.photo_library},
    {"title": "المراجعات", "icon": Icons.reviews},
  ];

  // تصنيفات مقدم الخدمة (API) (الخدمات = التصنيفات الرئيسية/الفرعية)
  List<ProviderServiceSubcategory> _providerSubcategories = const [];
  bool _servicesLoading = true;

  // ✅ معرض خدماتي (API)
  bool _portfolioLoading = true;
  List<ProviderPortfolioItem> _portfolioItems = const [];
  bool _spotlightsLoading = true;
  List<ProviderPortfolioItem> _spotlightItems = const [];

  String get providerName => _fullProfile?.displayName ?? widget.providerName ?? '—';

    String get providerCategory => (widget.providerCategory ?? '').trim();

  String get providerSubCategory =>
      (widget.providerSubCategory ?? '').trim();

  double get providerRating => _ratingAvgOverride ?? _fullProfile?.ratingAvg ?? widget.providerRating ?? 0.0;

  int get providerOperations => _fullProfile?.ratingCount ?? widget.providerOperations ?? 0;

  String get providerImage =>
      _fullProfile?.imageUrl?.trim().isNotEmpty == true
          ? _fullProfile!.imageUrl!.trim()
          : (widget.providerImage ?? '').trim();

    bool get providerVerified =>
      (_fullProfile?.isVerifiedBlue ?? false) ||
      (_fullProfile?.isVerifiedGreen ?? false) ||
      (widget.providerVerified ?? false);

    String get providerPhone =>
      _fullProfile?.phone?.trim().isNotEmpty == true
        ? _fullProfile!.phone!.trim()
        : (widget.providerPhone ?? '').trim();

  String get providerHandle {
    final raw = (_fullProfile?.username ?? '').trim();
    if (raw.isNotEmpty) return raw.startsWith('@') ? raw : '@$raw';
    final pid = (widget.providerId ?? '').trim();
    return pid.isNotEmpty ? '#$pid' : '—';
  }

  String get providerEnglishName => '';

  String get providerAccountType => providerCategory;

  String get providerServicesDetails {
    final bio = (_fullProfile?.bio ?? '').trim();
    if (bio.isNotEmpty) return bio;
    return 'لا توجد نبذة متاحة حالياً.';
  }

  int get providerYearsExperience => _fullProfile?.yearsExperience ?? 0;

  String get providerExperienceYears =>
      providerYearsExperience > 0 ? '$providerYearsExperience سنة' : '—';

  String get providerCityName => (_fullProfile?.city ?? '').trim();
  String get providerRegionName => 'منطقة الرياض';
  String get providerCountryName => 'المملكة العربية السعودية';

  double? get providerLat => _fullProfile?.lat ?? widget.providerLat;
  double? get providerLng => _fullProfile?.lng ?? widget.providerLng;

  bool _isRemoteImage(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') || p.startsWith('https://');
  }

  bool _isValidRemoteMediaUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (!_isRemoteImage(value)) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  Widget _providerAvatar() {
    if (providerImage.trim().isEmpty) {
      return const Icon(Icons.person, size: 36);
    }
    if (_isRemoteImage(providerImage)) {
      return Image.network(
        providerImage,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) => const Icon(Icons.person, size: 36),
      );
    }
    return Image.asset(
      providerImage,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stackTrace) => const Icon(Icons.person, size: 36),
    );
  }

  String get providerWebsite => '';

  String get providerInstagramUrl => '';

  String get providerXUrl => '';

  String get providerSnapchatUrl => '';

  ProviderProfile? _fullProfile;
  final SupportApi _supportApi = SupportApi();

  @override
  void initState() {
    super.initState();
    _syncCanManageGallery();
    if (widget.providerId != null) {
      _loadProviderData();
      _loadProviderSubcategories();
      _loadProviderPortfolio();
      _loadProviderSpotlights();
      _syncClientSocialState();
    }
  }

  Future<void> _syncCanManageGallery() async {
    final providerId = int.tryParse((widget.providerId ?? '').trim());
    if (providerId == null) return;
    try {
      final me = await AccountApi().me();
      final raw = me['provider_profile_id'];
      final int? myProviderId = raw is int ? raw : int.tryParse((raw ?? '').toString());
      if (!mounted) return;
      setState(() {
        _canManageGallery = myProviderId != null && myProviderId == providerId;
      });
    } catch (_) {
      // Best-effort: keep hidden.
    }
  }

  Future<void> _openManageGallery() async {
    if (!_canManageGallery) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProviderPortfolioManageScreen(),
      ),
    );
    await _loadProviderPortfolio();
  }

  Future<void> _syncClientSocialState() async {
    final providerId = int.tryParse((widget.providerId ?? '').trim());
    if (providerId == null) return;
    try {
      final api = ProvidersApi();
      final results = await Future.wait([
        api.getMyFollowingProviders(),
        api.getMyLikedProviders(),
        api.getMyFavoriteMedia(),
      ]);
      final following = results[0] as List<ProviderProfile>;
      final likedProviders = results[1] as List<ProviderProfile>;
      final favorites = results[2] as List<ProviderPortfolioItem>;
      if (!mounted) return;
      setState(() {
        _isFollowingProvider = following.any((p) => p.id == providerId);
        _isProviderLiked = likedProviders.any((p) => p.id == providerId);
        _favoritePortfolioIds = favorites.map((e) => e.id).toSet();
      });
    } catch (_) {}
  }

  Future<void> _toggleProviderLike() async {
    if (!await checkAuth(context)) return;
    if (!mounted) return;

    final providerId = int.tryParse((widget.providerId ?? '').trim());
    if (providerId == null || _isLikeBusy) return;

    setState(() => _isLikeBusy = true);

    final wasLiked = _isProviderLiked;
    final api = ProvidersApi();
    final ok = wasLiked
        ? await api.unlikeProvider(providerId)
        : await api.likeProvider(providerId);

    if (!mounted) return;
    setState(() => _isLikeBusy = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذرت العملية، حاول مرة أخرى')),
      );
      return;
    }

    setState(() {
      _isProviderLiked = !wasLiked;
      final current = _likesCount ?? 0;
      _likesCount = _isProviderLiked
          ? current + 1
          : (current > 0 ? current - 1 : 0);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isProviderLiked ? 'تم الإعجاب' : 'تم إلغاء الإعجاب'),
      ),
    );
  }

  Future<void> _toggleFollowProvider() async {
    if (!await checkAuth(context)) return;
    if (!mounted) return;
    final providerId = int.tryParse((widget.providerId ?? '').trim());
    if (providerId == null || _isFollowBusy) return;

    setState(() => _isFollowBusy = true);
    final api = ProvidersApi();
    final ok = _isFollowingProvider
        ? await api.unfollowProvider(providerId)
        : await api.followProvider(providerId);
    if (!mounted) return;
    setState(() => _isFollowBusy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذرت العملية، حاول مرة أخرى')),
      );
      return;
    }

    setState(() {
      _isFollowingProvider = !_isFollowingProvider;
      final current = _followersCount ?? 0;
      _followersCount = _isFollowingProvider
          ? current + 1
          : (current > 0 ? current - 1 : 0);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFollowingProvider ? 'تمت المتابعة بنجاح' : 'تم إلغاء المتابعة',
        ),
      ),
    );
  }

  Future<void> _togglePortfolioFavorite(ProviderPortfolioItem item) async {
    if (!await checkAuth(context)) return;
    if (!mounted) return;
    if (_portfolioFavoriteBusyIds.contains(item.id)) return;
    setState(() => _portfolioFavoriteBusyIds.add(item.id));

    final isFav = _favoritePortfolioIds.contains(item.id);
    final api = ProvidersApi();
    final ok = isFav
        ? await api.unlikePortfolioItem(item.id)
        : await api.likePortfolioItem(item.id);
    if (!mounted) return;
    setState(() => _portfolioFavoriteBusyIds.remove(item.id));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث التفضيل')),
      );
      return;
    }
    setState(() {
      if (isFav) {
        _favoritePortfolioIds.remove(item.id);
      } else {
        _favoritePortfolioIds.add(item.id);
      }
    });
  }

  void _toggleHighlightFavorite(int index) {
    setState(() {
      if (_favoriteHighlightIndexes.contains(index)) {
        _favoriteHighlightIndexes.remove(index);
      } else {
        _favoriteHighlightIndexes.add(index);
      }
    });
  }

  // Highlights are separate from portfolio and loaded from dedicated API.
  List<ProviderPortfolioItem> get _highlightItems {
    return _spotlightItems.where((item) {
      final fileUrlOk = _isValidRemoteMediaUrl(item.fileUrl);
      if (!fileUrlOk) return false;
      final isVideo = item.fileType.toLowerCase() == 'video';
      if (!isVideo) return true;
      final thumb = (item.thumbnailUrl ?? '').trim();
      // Video can still be valid without thumbnail; the player uses fileUrl.
      return thumb.isEmpty || _isValidRemoteMediaUrl(thumb);
    }).toList(growable: false);
  }

  Future<void> _loadProviderSpotlights() async {
    final id = int.tryParse(widget.providerId ?? '');
    if (id == null) return;

    if (mounted) {
      setState(() => _spotlightsLoading = true);
    }

    try {
      final items = await ProvidersApi().getProviderSpotlights(id);
      if (!mounted) return;
      setState(() {
        _spotlightItems = items;
        _spotlightsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _spotlightItems = const [];
        _spotlightsLoading = false;
      });
    }
  }

  Future<void> _loadProviderPortfolio() async {
    final id = int.tryParse(widget.providerId ?? '');
    if (id == null) return;

    if (mounted) {
      setState(() => _portfolioLoading = true);
    }

    try {
      final items = await ProvidersApi().getProviderPortfolio(id);
      if (!mounted) return;
      setState(() {
        _portfolioItems = items;
        _portfolioLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _portfolioItems = const [];
        _portfolioLoading = false;
      });
    }
  }

  Future<void> _loadProviderData() async {
    try {
      final id = int.tryParse((widget.providerId ?? '').trim());
      if (id == null) return;
      
      final api = ProvidersApi();
      final results = await Future.wait<dynamic>([
        api.getProviderDetail(id),
        api.getProviderPublicStats(id),
      ]);
      final profile = results[0] as ProviderProfile?;
      final publicStats = results[1] as Map<String, dynamic>?;
      if (profile != null && mounted) {
        int? completedFromStats;
        int? followersFromStats;
        int? followingFromStats;
        int? likesFromStats;
        int? ratingCountFromStats;
        double? ratingAvgFromStats;
        final rawCompleted = publicStats?['completed_requests'];
        final rawFollowers = publicStats?['followers_count'];
        final rawFollowing = publicStats?['following_count'];
        final rawLikes = publicStats?['likes_count'];
        final rawRatingCount = publicStats?['rating_count'];
        final rawRatingAvg = publicStats?['rating_avg'];
        if (rawCompleted is int) {
          completedFromStats = rawCompleted;
        } else if (rawCompleted != null) {
          completedFromStats = int.tryParse(rawCompleted.toString());
        }
        if (rawFollowers is int) {
          followersFromStats = rawFollowers;
        } else if (rawFollowers != null) {
          followersFromStats = int.tryParse(rawFollowers.toString());
        }
        if (rawFollowing is int) {
          followingFromStats = rawFollowing;
        } else if (rawFollowing != null) {
          followingFromStats = int.tryParse(rawFollowing.toString());
        }
        if (rawLikes is int) {
          likesFromStats = rawLikes;
        } else if (rawLikes != null) {
          likesFromStats = int.tryParse(rawLikes.toString());
        }
        if (rawRatingCount is int) {
          ratingCountFromStats = rawRatingCount;
        } else if (rawRatingCount != null) {
          ratingCountFromStats = int.tryParse(rawRatingCount.toString());
        }
        if (rawRatingAvg is num) {
          ratingAvgFromStats = rawRatingAvg.toDouble();
        } else if (rawRatingAvg != null) {
          ratingAvgFromStats = double.tryParse(rawRatingAvg.toString());
        }

        setState(() {
          _fullProfile = profile;
          _completedRequests = completedFromStats ?? profile.completedRequests;
          _followersCount = followersFromStats ?? profile.followersCount;
          _followingCount = followingFromStats ?? profile.followingCount;
          _likesCount = likesFromStats ?? profile.likesCount;
          _reviewersCount = ratingCountFromStats ?? profile.ratingCount;
          _ratingAvgOverride = ratingAvgFromStats;
        });
      }
    } catch (e) {
      debugPrint('Error loading provider: $e');
    }
  }

  String _formatPhoneE164(String rawPhone) {
    final phone = rawPhone.replaceAll(RegExp(r'\s+'), '');
    if (phone.startsWith('+')) return phone;

    if (phone.startsWith('05') && phone.length == 10) {
      return '+966${phone.substring(1)}';
    }
    if (phone.startsWith('5') && phone.length == 9) {
      return '+966$phone';
    }
    return phone;
  }

  Future<void> _openPhoneCall() async {
    final e164 = _formatPhoneE164(providerPhone);
    final uri = Uri(scheme: 'tel', path: e164);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الاتصال')),
    );
  }

  String _buildWhatsAppMessage() {
    final buffer = StringBuffer();
    buffer.writeln('@${providerName.replaceAll(' ', '')}');
    buffer.writeln('السلام عليكم');
    buffer.writeln('أتواصل معك بخصوص خدماتك المعروضة في منصة (نوافذ)');
    return buffer.toString().trim();
  }

  Future<void> _openWhatsApp() async {
    final target = (_fullProfile?.whatsapp ?? '').trim().isNotEmpty
        ? _fullProfile!.whatsapp!.trim()
        : providerPhone;
    await WhatsAppHelper.open(
      context: context,
      contact: target,
      message: _buildWhatsAppMessage(),
    );
  }

  Future<void> _openInAppChat() async {
    if (!await checkAuth(context)) return;
    final providerId = (widget.providerId ?? '').trim();
    if (providerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المحادثة: لا يوجد مزود مرتبط.')),
      );
      return;
    }
    if (!mounted) return;

    // Open direct chat with provider (no request required)
    try {
      final api = MessagingApi();
      final thread = await api.getOrCreateDirectThread(int.parse(providerId));
      final threadId = thread['id'] as int?;
      if (threadId == null) throw Exception('no thread id');
      if (!mounted) return;
      ChatNav.openThread(
        context,
        threadId: threadId,
        name: providerName,
        isOnline: _fullProfile?.isOnline == true,
        isDirect: true,
        peerId: providerId,
        peerName: providerName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المحادثة. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _showShareAndReportSheet() async {
    final e164 = _formatPhoneE164(providerPhone);
    final shareLink = '${ApiConfig.baseUrl}/provider/${widget.providerId ?? ''}';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.qr_code_2, size: 22, color: Colors.black87),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مشاركة نافذة مقدم الخدمة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: mainColor.withValues(alpha: 0.25)),
                    borderRadius: BorderRadius.circular(14),
                    color: mainColor.withValues(alpha: 0.04),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: QrImageView(
                            data: shareLink,
                            padding: const EdgeInsets.all(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        e164,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: shareLink));
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم نسخ الرابط')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('نسخ الرابط', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Share.share(shareLink);
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('مشاركة', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showPlatformReportDialog(
                      context: context,
                      title: 'إبلاغ عن مزود خدمة',
                      reportedEntityLabel: 'بيانات المبلغ عنه:',
                      reportedEntityValue: '$providerName ($providerHandle)',
                      contextLabel: 'نوع البلاغ',
                      contextValue: 'مزود خدمة',
                      onSubmit: ({required reason, required details}) async {
                        if (!await checkAuth(context)) return;
                        if (!mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final res = await _supportApi.createComplaintTicket(
                            reason: reason,
                            details: details,
                            contextLabel: 'نوع البلاغ',
                            contextValue: 'مزود خدمة',
                            reportedEntityValue: '$providerName ($providerHandle)',
                          );
                          if (!mounted) return;
                          final code = (res['code'] ?? '').toString().trim();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                code.isEmpty
                                    ? 'تم إرسال البلاغ بنجاح'
                                    : 'تم إرسال البلاغ: $code',
                              ),
                            ),
                          );
                        } catch (_) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('تعذر إرسال البلاغ حالياً')),
                          );
                        }
                      },
                    );
                  },
                  leading: const Icon(Icons.flag_outlined, color: Colors.red),
                  title: const Text('الإبلاغ عن مقدم الخدمة', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFollowersList() async {
    final providerId = int.tryParse((widget.providerId ?? '').trim());
    if (providerId == null) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final countText = _followersCount?.toString() ?? '—';
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded, color: Colors.black87),
                      const SizedBox(width: 10),
                      Text(
                        'متابعون ($countText)',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<UserSummary>>(
                    future: ProvidersApi().getProviderFollowers(providerId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final list = snapshot.data ?? [];
                      if (list.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'لا يوجد متابعون حالياً',
                              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, i) {
                          final user = list[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(user.displayName[0].toUpperCase()),
                            ),
                            title: Text(
                              user.displayName,
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            subtitle: user.username != null
                                ? Text(
                                    '@${user.username}',
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFollowingList() async {
    final providerId = int.tryParse((widget.providerId ?? '').trim());
    if (providerId == null) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final countText = _followingCount?.toString() ?? '—';
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'يتابع ($countText)',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<ProviderProfile>>(
                    future: ProvidersApi().getProviderFollowing(providerId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final list = snapshot.data ?? [];
                      if (list.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'لا يتابع أحداً حالياً',
                              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, i) {
                          final provider = list[i];
                          final displayName = provider.displayName ?? 'مزود';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: provider.imageUrl != null && provider.imageUrl!.trim().isNotEmpty
                                  ? NetworkImage(provider.imageUrl!)
                                  : null,
                              child: provider.imageUrl == null || provider.imageUrl!.trim().isEmpty
                                  ? Text(displayName[0].toUpperCase())
                                  : null,
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            subtitle: provider.city != null
                                ? Text(
                                    provider.city!,
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                  )
                                : null,
                            trailing: provider.isVerifiedBlue || provider.isVerifiedGreen
                                ? Icon(
                                    Icons.verified,
                                    size: 16,
                                    color: provider.isVerifiedBlue ? Colors.blue : Colors.green,
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProviderProfileScreen(
                                    providerId: provider.id.toString(),
                                    providerName: provider.displayName,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: const CustomAppBar(title: 'المزود'),
        drawer: const CustomDrawer(),
        body: SingleChildScrollView(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 128,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          const Color(0xFF8F6ED6),
                          const Color(0xFF7F57CF),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    left: 12,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: _isFollowingProvider
                              ? 'إلغاء المتابعة'
                              : 'متابعة',
                          onPressed: _isFollowBusy ? null : _toggleFollowProvider,
                          icon: _isFollowBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _isFollowingProvider
                                      ? Icons.person_remove_alt_1_rounded
                                      : Icons.person_add_alt_1_rounded,
                                  color: Colors.white,
                                ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'مشاركة/إبلاغ',
                          onPressed: _showShareAndReportSheet,
                          icon: const Icon(Icons.ios_share, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: -42,
                    right: 18,
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: bgColor,
                      child: ClipOval(
                        child: SizedBox(
                          width: 78,
                          height: 78,
                          child: _providerAvatar(),
                        ),
                      ),
                    ),
                  ),
                  if (providerVerified)
                    Positioned(
                      bottom: -12,
                      right: 24,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: mainColor.withValues(alpha: 0.25), width: 1),
                        ),
                        child: Center(
                          child: Icon(Icons.check_circle, color: mainColor, size: 18),
                        ),
                      ),
                    ),
                  if (_fullProfile?.isOnline == true)
                    Positioned(
                      bottom: -12,
                      right: 78,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: bgColor ?? Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 52),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Text(
                      providerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2, size: 14, color: secondaryTextColor),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.star,
                          size: 17,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          providerRating.toStringAsFixed(1),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${_reviewersCount?.toString() ?? '0'})',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_completedRequests ?? providerOperations} عملية',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _circleStat(
                      icon: Icons.business_center_outlined,
                      value: _completedRequests ?? widget.providerOperations ?? 0,
                      onTap: () {},
                      isDark: isDark,
                    ),
                    _circleStat(
                      icon: Icons.groups_rounded,
                      value: _followersCount,
                      onTap: _showFollowersList,
                      isDark: isDark,
                    ),
                    _circleStat(
                      icon: Icons.person_add_alt_1_rounded,
                      value: _followingCount,
                      onTap: _showFollowingList,
                      isDark: isDark,
                    ),
                    _circleStat(
                      icon: _isLikeBusy
                          ? Icons.hourglass_top_rounded
                          : (_isProviderLiked
                              ? Icons.thumb_up_alt
                              : Icons.thumb_up_alt_outlined),
                      value: _likesCount,
                      onTap: _isLikeBusy ? () {} : _toggleProviderLike,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              if (_spotlightsLoading || _highlightItems.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _highlightsRow(isDark: isDark),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!await checkFullClient(context)) return;
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServiceRequestFormScreen(
                            providerName: providerName,
                            providerId: widget.providerId,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'طلب خدمة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tabs.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final isSelected = _selectedTabIndex == index;
                    final bg = isSelected
                        ? mainColor.withValues(alpha: 0.14)
                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade100);
                    final border = isSelected
                        ? mainColor.withValues(alpha: 0.35)
                      : (isDark ? Colors.grey.shade700 : Colors.grey.shade200);
                    final iconColor = isSelected ? mainColor : (isDark ? Colors.grey.shade300 : Colors.grey.shade700);
                    final titleColor = isSelected ? mainColor : textColor;

                    return InkWell(
                      onTap: () => setState(() => _selectedTabIndex = index),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 98),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(tabs[index]['icon'], size: 20, color: iconColor),
                            const SizedBox(height: 3),
                            if (_canManageGallery && index == 2)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      tabs[index]['title'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        height: 1.0,
                                        fontWeight: FontWeight.w800,
                                        color: titleColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        if (!mounted) return;
                                        setState(() => _selectedTabIndex = 2);
                                        await _openManageGallery();
                                      },
                                      borderRadius: BorderRadius.circular(999),
                                      child: Padding(
                                        padding: const EdgeInsets.all(1),
                                        child: Icon(
                                          Icons.settings_outlined,
                                          size: 15,
                                          color: titleColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                tabs[index]['title'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  height: 1.0,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTabContent(),
              ),
              const SizedBox(height: 30),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleStat({
    required IconData icon,
    required int? value,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final ring = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value == null ? '—' : value.toString(),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _DashedCirclePainter(
                color: ring,
                strokeWidth: 2,
                dashLength: 5,
                gapLength: 4,
              ),
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Icon(icon, color: mainColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightsRow({required bool isDark}) {
    final items = _highlightItems;
    final textColor = isDark ? Colors.white : Colors.black;
    final sub = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    if (_spotlightsLoading) {
      return const SizedBox(
        height: 82,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'لمحات مقدم الخدمة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            const Spacer(),
            Text(
              'اسحب يمين/يسار',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: sub,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              final isFav = _favoriteHighlightIndexes.contains(index);
              final isVideo = item.fileType.toLowerCase() == 'video';
              final previewUrl = isVideo
                  ? ((item.thumbnailUrl ?? '').trim().isNotEmpty
                      ? item.thumbnailUrl!.trim()
                      : item.fileUrl)
                  : item.fileUrl;
              final hasPreview = _isValidRemoteMediaUrl(previewUrl);
              return InkWell(
                onTap: () => _openHighlights(index),
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        image: hasPreview
                            ? DecorationImage(
                                image: NetworkImage(previewUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: hasPreview ? null : Colors.grey.shade200,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.18),
                        ),
                          child: Center(
                            child: Icon(
                            hasPreview
                                ? (isVideo ? Icons.play_circle_fill : Icons.image_outlined)
                                : Icons.broken_image_outlined,
                            size: 34,
                            color: hasPreview ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _toggleHighlightFavorite(index),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openHighlights(int initialIndex) async {
    final items = _highlightItems;
    if (items.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, items.length - 1);
    final item = items[safeIndex];
    final mediaUrl = item.fileUrl.trim();
    if (!_isValidRemoteMediaUrl(mediaUrl)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح اللمحة: رابط الوسائط غير صالح')),
      );
      return;
    }
    if (item.fileType.toLowerCase() == 'video') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NetworkVideoPlayerScreen(
            url: mediaUrl,
            title: providerName,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                mediaUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black87,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _profileTab();
      case 1:
        return _servicesTab();
      case 2:
        return _galleryTab();
      case 3:
        final int? providerId =
            _fullProfile?.id ?? int.tryParse((widget.providerId ?? '').toString());
        return ReviewsTab(
          providerId: providerId,
          embedded: true,
          onOpenChat: (customerName) async {
            if (!context.mounted) return;
            await ChatNav.openInbox(context);
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _profileTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey.shade800 : Colors.white;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final subtleColor = isDark ? Colors.grey.shade800 : const Color(0xFFF7F4FB);

    final hasPhone = providerPhone.trim().isNotEmpty;
    final hasWhatsApp =
        ((_fullProfile?.whatsapp ?? '').trim().isNotEmpty) ||
        hasPhone;
    final lat = providerLat;
    final lng = providerLng;
    final city = providerCityName.trim().isEmpty ? '—' : providerCityName;
    final aboutText = providerServicesDetails.trim().isEmpty
        ? 'لا توجد نبذة مضافة حالياً'
        : providerServicesDetails.trim();
    final yearsText = providerExperienceYears.trim().isEmpty
        ? '—'
        : providerExperienceYears.trim();

    Widget infoTile({
      required IconData icon,
      required String title,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: subtleColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: mainColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget actionButton({
      required VoidCallback? onPressed,
      required Widget icon,
      required String label,
      required Color backgroundColor,
      required Color foregroundColor,
    }) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                mainColor.withValues(alpha: 0.18),
                mainColor.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: mainColor.withValues(alpha: 0.24)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: mainColor.withValues(alpha: 0.25)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _providerAvatar(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      providerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          providerHandle,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: secondaryTextColor,
                          ),
                        ),
                        if (providerVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: mainColor.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 13, color: mainColor),
                                const SizedBox(width: 4),
                                Text(
                                  'موثق',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: mainColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.badge_outlined, size: 18, color: mainColor),
                  const SizedBox(width: 8),
                  Text(
                    'نبذة عن مقدم الخدمة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                aboutText,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: secondaryTextColor,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: infoTile(
                icon: Icons.location_on_outlined,
                title: 'المدينة',
                value: city,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: infoTile(
                icon: Icons.workspace_premium_outlined,
                title: 'سنوات الخبرة',
                value: yearsText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: actionButton(
                onPressed: hasPhone ? _openPhoneCall : null,
                icon: const Icon(Icons.call_rounded, size: 18),
                label: hasPhone ? 'اتصال' : 'رقم غير متاح',
                backgroundColor: mainColor,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: actionButton(
                onPressed: hasWhatsApp ? _openWhatsApp : null,
                icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 17),
                label: 'واتساب',
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openInAppChat,
            icon: Icon(Icons.forum_outlined, size: 18, color: mainColor),
            label: Text(
              'محادثة داخل التطبيق',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: mainColor,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: mainColor.withValues(alpha: 0.35)),
              backgroundColor: mainColor.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        if (lat != null && lng != null) ...[
          const SizedBox(height: 12),
          _formCard(
            cardColor: cardColor,
            borderColor: borderColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.map_outlined, size: 18, color: mainColor),
                    const SizedBox(width: 8),
                    Text(
                      'موقع مقدم الخدمة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(lat, lng),
                        initialZoom: 13,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                          userAgentPackageName: 'com.nawafeth.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(lat, lng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin, size: 40, color: Colors.red),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _formCard({
    required Color cardColor,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _servicesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    Widget header() {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'التصنيفات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          TextButton.icon(
            onPressed: _servicesLoading ? null : _loadProviderSubcategories,
            icon: Icon(Icons.refresh, color: mainColor),
            label: Text(
              'تحديث',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: mainColor,
              ),
            ),
          ),
        ],
      );
    }

    if (_servicesLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            header(),
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    if (_providerSubcategories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            header(),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                'لا توجد تصنيفات محددة حالياً',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadProviderSubcategories,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        header(),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _providerSubcategories.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final s = _providerSubcategories[index];
            final cat = (s.categoryName ?? '').trim();
            final subtitle = cat.isNotEmpty ? cat : '—';

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade700
                      : Colors.grey.shade200,
                ),
              ),
              child: ListTile(
                title: Text(
                  s.name,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  ),
                ),
                subtitle: Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                trailing: const Icon(Icons.label_outline),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _loadProviderSubcategories() async {
    final id = int.tryParse((widget.providerId ?? '').trim());
    if (id == null) {
      if (!mounted) return;
      setState(() {
        _providerSubcategories = const [];
        _servicesLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _servicesLoading = true);

    try {
      final subs = await ProvidersApi().getProviderSubcategories(id);
      if (!mounted) return;
      setState(() {
        _providerSubcategories = subs;
        _servicesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _providerSubcategories = const [];
        _servicesLoading = false;
      });
    }
  }

  Widget _galleryTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey.shade800 : Colors.white;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final videosCount = _portfolioItems
        .where((e) => e.fileType.toLowerCase() == 'video')
        .length;
    final imagesCount = _portfolioItems.length - videosCount;

    Widget statChip({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: mainColor),
            const SizedBox(width: 6),
            Text(
              '$label: $value',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                mainColor.withValues(alpha: isDark ? 0.28 : 0.18),
                mainColor.withValues(alpha: isDark ? 0.16 : 0.09),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mainColor.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.8),
                ),
                child: Icon(Icons.photo_library_outlined, color: mainColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'معرض خدماتي',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'صور وفيديوهات أعمال مقدم الخدمة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            statChip(
              icon: Icons.grid_view_rounded,
              label: 'الكل',
              value: _portfolioItems.length.toString(),
            ),
            statChip(
              icon: Icons.image_outlined,
              label: 'صور',
              value: imagesCount.toString(),
            ),
            statChip(
              icon: Icons.videocam_outlined,
              label: 'فيديو',
              value: videosCount.toString(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_portfolioLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_portfolioItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.perm_media_outlined,
                  color: mainColor.withValues(alpha: 0.75),
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  'لا يوجد محتوى في المعرض حالياً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'سيظهر هنا ما يضيفه المزود من صور وفيديوهات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loadProviderPortfolio,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'تحديث',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 640 ? 3 : 2;
              final itemWidth =
                  (constraints.maxWidth - ((crossAxisCount - 1) * 12)) /
                  crossAxisCount;
              // Extra height on 2-column layout to absorb long Arabic captions
              // and action labels without bottom overflow on small screens.
              final itemHeight = crossAxisCount == 3 ? 238.0 : 280.0;
              final ratio = itemWidth / itemHeight;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _portfolioItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: ratio,
                ),
                itemBuilder: (context, index) {
                  final item = _portfolioItems[index];
                  final isVideo = item.fileType.toLowerCase() == 'video';
                  final isFav = _favoritePortfolioIds.contains(item.id);

                  return InkWell(
                    onTap: () async {
                      if (isVideo) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NetworkVideoPlayerScreen(
                              url: item.fileUrl,
                              title: providerName,
                            ),
                          ),
                        );
                        return;
                      }
                      if (!mounted) return;
                      showDialog<void>(
                        context: context,
                        builder: (dialogContext) {
                          return Dialog(
                            insetPadding: const EdgeInsets.all(12),
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            child: InteractiveViewer(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  item.fileUrl,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                  child: Image.network(
                                    item.fileUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey.shade200,
                                      child: Center(
                                        child: Icon(
                                          isVideo ? Icons.videocam_rounded : Icons.image,
                                          size: 34,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (isVideo)
                                  const Positioned.fill(
                                    child: Center(
                                      child: Icon(Icons.play_circle_fill, size: 46, color: Colors.white),
                                    ),
                                  ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _togglePortfolioFavorite(item),
                                      borderRadius: BorderRadius.circular(999),
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.45),
                                          shape: BoxShape.circle,
                                        ),
                                        child: _portfolioFavoriteBusyIds.contains(item.id)
                                            ? const Padding(
                                                padding: EdgeInsets.all(8),
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : Icon(
                                                isFav ? Icons.favorite : Icons.favorite_border,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.caption.trim().isEmpty ? (isVideo ? 'فيديو' : 'صورة') : item.caption,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 1,
                                  color: borderColor,
                                ),
                                const SizedBox(height: 8),
                                LayoutBuilder(
                                  builder: (context, actionConstraints) {
                                    final compact = actionConstraints.maxWidth < 185;
                                    final columns = compact ? 2 : 3;
                                    final spacing = 6.0;
                                    final itemWidth =
                                        (actionConstraints.maxWidth - (spacing * (columns - 1))) / columns;

                                    return Wrap(
                                      spacing: spacing,
                                      runSpacing: spacing,
                                      children: [
                                        SizedBox(
                                          width: itemWidth,
                                          child: InkWell(
                                            onTap: _isLikeBusy ? null : _toggleProviderLike,
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  if (_isLikeBusy)
                                                    const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  else
                                                    Icon(
                                                      _isProviderLiked ? Icons.favorite : Icons.favorite_border,
                                                      size: 16,
                                                      color: _isProviderLiked ? Colors.red : mainColor,
                                                    ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'إعجاب',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: itemWidth,
                                          child: InkWell(
                                            onTap: () => _togglePortfolioFavorite(item),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    isFav ? Icons.bookmark : Icons.bookmark_border,
                                                    size: 16,
                                                    color: isFav ? mainColor : secondaryTextColor,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'المفضلة',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: itemWidth,
                                          child: InkWell(
                                            onTap: () => setState(() => _selectedTabIndex = 0),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 8,
                                                    backgroundColor: Colors.grey.shade200,
                                                    child: ClipOval(
                                                      child: SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child: _providerAvatar(),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'حساب المزود',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: compact ? 9 : 9.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final radius = (size.shortestSide / 2) - strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * 3.141592653589793 * radius;
    final dashCount =
        (circumference / (dashLength + gapLength)).floor().clamp(8, 200);
    final sweep = (2 * 3.141592653589793) / dashCount;
    final dashSweep = sweep * (dashLength / (dashLength + gapLength));

    for (int i = 0; i < dashCount; i++) {
      final start = (sweep * i);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
