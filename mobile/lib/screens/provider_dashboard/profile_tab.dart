import 'package:flutter/material.dart';

import 'package:nawafeth/constants/saudi_cities.dart';
import 'package:nawafeth/models/excellence_badge_model.dart';
import 'package:nawafeth/models/provider_profile_model.dart';
import 'package:nawafeth/models/user_profile.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/screens/registration/steps/content_step.dart';
import 'package:nawafeth/widgets/excellence_badges_wrap.dart';
import 'package:nawafeth/widgets/platform_top_bar.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with TickerProviderStateMixin {
  final Color mainColor = Colors.deepPurple;
  late TabController _tabController;

  // ────── حالة التحميل ──────
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  UserProfile? _userProfile;
  ProviderProfileModel? _providerProfile;

  // ────── بيانات قابلة للتعديل ──────
  final Map<String, String> data = {};
  final Map<String, bool> isEditing = {};
  final Map<String, TextEditingController> controllers = {};

  // ────── ربط مفاتيح الحقول بحقول الـ API ──────
  static const Map<String, String> _fieldToApiKey = {
    'fullName': 'display_name',
    'accountType': 'provider_type',
    'about': 'bio',
    'specialization': 'about_details',
    'experience': 'years_experience',
    'languages': 'languages',
    'location': 'city',
    'details': 'about_details',
    'qualification': 'qualifications',
    'website': 'website',
    'social': 'social_links',
    'phone': 'whatsapp',
    'keywords': 'seo_keywords',
  };

  void _openPortfolio() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContentStep(
          onBack: () => Navigator.pop(context),
          onNext: () => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// جلب بيانات المزود من الـ API
  Future<void> _loadProfile({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    // جلب بيانات المستخدم وملف المزود بالتوازي لتقليل زمن التحميل.
    final meFuture = ProfileService.fetchMyProfile();
    final providerFuture = ProfileService.fetchProviderProfile();

    final meResult = await meFuture;
    final providerResult = await providerFuture;
    if (!mounted) return;

    if (meResult.isSuccess && meResult.data != null) {
      _userProfile = meResult.data;
    }

    if (providerResult.isSuccess && providerResult.data != null) {
      _providerProfile = providerResult.data;
      _populateFields();
    } else if (!silent) {
      setState(() {
        _isLoading = false;
        _errorMessage = providerResult.error ?? 'تعذر جلب بيانات الملف الشخصي';
      });
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// تعبئة الحقول من بيانات الـ API
  void _populateFields() {
    final p = _providerProfile;
    if (p == null) return;

    final raw = <String, String>{
      'fullName': p.displayName,
      'accountType': _providerTypeLabel(p.providerType),
      'about': p.bio,
      'specialization': p.aboutDetails ?? '',
      'experience': p.yearsExperience > 0 ? '${p.yearsExperience} سنوات' : '',
      'languages': p.languages.isNotEmpty
          ? p.languages
              .map((e) => e is Map ? (e['name'] ?? e.toString()) : e.toString())
              .join('، ')
          : '',
      'location': p.city,
      'details': p.aboutDetails ?? '',
      'qualification': p.qualifications.isNotEmpty
          ? p.qualifications
              .map((e) => e is Map ? (e['title'] ?? e.toString()) : e.toString())
              .join('، ')
          : '',
      'website': p.website ?? '',
      'social': p.socialLinks.isNotEmpty
          ? p.socialLinks
              .map((e) => e is Map ? (e['url'] ?? e.toString()) : e.toString())
              .join('\n')
          : '',
      'phone': p.whatsapp ?? _userProfile?.phone ?? '',
      'keywords': p.seoKeywords,
    };

    data.clear();
    for (final entry in raw.entries) {
      data[entry.key] = entry.value;
      if (controllers.containsKey(entry.key)) {
        controllers[entry.key]!.text = entry.value;
      } else {
        controllers[entry.key] = TextEditingController(text: entry.value);
      }
      isEditing[entry.key] = false;
    }
  }

  String _providerTypeLabel(String type) {
    switch (type) {
      case 'individual':
        return 'فرد';
      case 'company':
        return 'منشأة';
      case 'freelancer':
        return 'مستقل';
      default:
        return type;
    }
  }

  /// حفظ حقل واحد عبر PATCH
  Future<void> _saveField(String key) async {
    final apiKey = _fieldToApiKey[key];
    if (apiKey == null) return;

    final value = controllers[key]?.text.trim() ?? '';

    Map<String, dynamic> payload = {};
    switch (apiKey) {
      case 'years_experience':
        final parsed = int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
        if (parsed != null) {
          payload[apiKey] = parsed;
        } else {
          _showSnack('أدخل رقمًا صحيحًا لسنوات الخبرة', isError: true);
          return;
        }
        break;
      case 'languages':
        payload[apiKey] = value
            .split(RegExp(r'[،,]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => {'name': s})
            .toList();
        break;
      case 'qualifications':
        payload[apiKey] = value
            .split(RegExp(r'[،,]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => {'title': s})
            .toList();
        break;
      case 'social_links':
        payload[apiKey] = value
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => {'url': s})
            .toList();
        break;
      default:
        payload[apiKey] = value;
    }

    setState(() => _isSaving = true);

    final result = await ProfileService.updateProviderProfile(payload);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess && result.data != null) {
      _providerProfile = result.data;
      _populateFields();
      _showSnack('تم الحفظ بنجاح');
    } else {
      _showSnack(result.error ?? 'فشل في الحفظ', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<ExcellenceBadgeModel> get _excellenceBadges =>
      _providerProfile?.excellenceBadges ?? const [];

  List<ExcellenceBadgeModel> _recentlyAwardedBadges({int days = 14}) {
    final now = DateTime.now();
    return _excellenceBadges.where((badge) {
      final raw = (badge.awardedAt ?? '').trim();
      if (raw.isEmpty) return false;
      final awardedAt = DateTime.tryParse(raw);
      if (awardedAt == null) return false;
      final diff = now.difference(awardedAt);
      return !diff.isNegative && diff.inDays <= days;
    }).toList(growable: false);
  }

  Widget _buildProfileIdentityCard() {
    final profile = _providerProfile;
    if (profile == null) return const SizedBox.shrink();

    final badges = _excellenceBadges;
    final recentBadges = _recentlyAwardedBadges();
    final displayName = profile.displayName.trim().isNotEmpty
        ? profile.displayName.trim()
        : 'مزود الخدمة';
    final topBadge = badges.isNotEmpty ? badges.first : null;
    final profileImage = (profile.profileImage ?? '').trim();
    final hasImage = profileImage.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFFFFFF), Color(0xFFF6F1FF)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: mainColor.withAlpha(25),
                    backgroundImage: hasImage ? NetworkImage(profileImage) : null,
                    child: hasImage
                        ? null
                        : Text(
                            displayName.substring(0, 1),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: mainColor,
                              fontSize: 20,
                            ),
                          ),
                  ),
                  if (topBadge != null)
                    Positioned(
                      top: -6,
                      left: -4,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 100),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          topBadge.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF17192D),
                      ),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ExcellenceBadgesWrap(
                        badges: badges,
                        compact: true,
                        alignment: WrapAlignment.start,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (recentBadges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8C566)),
              ),
              child: Text(
                'تهانينا! حصلت على شارة ${recentBadges.first.name} وتم عرضها الآن في نافذتي.',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Color(0xFF6B4C05),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildField(
    String key,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool readOnly = false,
  }) {
    final editing = isEditing[key] ?? false;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: mainColor.withAlpha(25),
                  child: Icon(icon, color: mainColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (!readOnly)
                  _isSaving && editing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: Icon(
                            editing ? Icons.check_circle : Icons.edit,
                            color: editing ? Colors.green : mainColor,
                          ),
                          onPressed: () {
                            if (editing) {
                              data[key] = controllers[key]!.text;
                              _saveField(key);
                            }
                            setState(() {
                              isEditing[key] = !editing;
                            });
                          },
                        ),
              ],
            ),
            const SizedBox(height: 12),
            editing
                ? (key == 'location'
                    ? DropdownButtonFormField<String>(
                        initialValue: SaudiCities.all.contains(controllers[key]?.text)
                            ? controllers[key]!.text
                            : null,
                        decoration: InputDecoration(
                          hintText: 'اختر المدينة',
                          hintStyle: const TextStyle(fontFamily: 'Cairo'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: mainColor),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          isDense: true,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        isExpanded: true,
                        menuMaxHeight: 300,
                        items: SaudiCities.all
                            .map((city) => DropdownMenuItem(
                                  value: city,
                                  child: Text(city,
                                      style: const TextStyle(fontFamily: 'Cairo')),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              controllers[key]!.text = v;
                            });
                          }
                        },
                      )
                    : TextField(
                        controller: controllers[key],
                        maxLines: maxLines,
                        style: const TextStyle(fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          hintText: 'أدخل $label',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: mainColor),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          isDense: true,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ))
                : Text(
                    (controllers[key]?.text ?? '').isEmpty
                        ? '—'
                        : controllers[key]!.text,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      color: (controllers[key]?.text ?? '').isEmpty
                          ? Colors.black38
                          : Colors.black87,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget buildSection(List<Map<String, dynamic>> fields) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildProfileIdentityCard(),
        InkWell(
          onTap: _openPortfolio,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: mainColor.withAlpha(25),
                  child: Icon(Icons.photo_library_outlined, color: mainColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معرض الأعمال',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'تحكم بمحتوى المعرض الذي يظهر للعملاء',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: mainColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...fields
            .map(
              (field) => buildField(
                field['key'],
                field['label'],
                field['icon'],
                maxLines: field['multiline'] == true ? 3 : 1,
                readOnly: field['readOnly'] == true,
              ),
            )
            ,
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(118),
          child: Container(
            color: mainColor,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  PlatformTopBar(
                    overlay: true,
                    pageLabel: 'الملف الشخصي',
                    showBackButton: true,
                    showNotificationAction: false,
                    showChatAction: false,
                    trailingActions: [
                      IconButton(
                        tooltip: 'معرض الأعمال',
                        onPressed: _openPortfolio,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  TabBar(
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'معلومات الحساب'),
                      Tab(text: 'معلومات عامة'),
                      Tab(text: 'معلومات إضافية'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        backgroundColor: const Color(0xFFF4F4F4),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
            : (_errorMessage != null && _providerProfile == null)
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: () => _loadProfile(silent: true),
                    color: mainColor,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        buildSection([
                          {
                            "key": "fullName",
                            "label": "اسم العرض",
                            "icon": Icons.person,
                          },
                          {
                            "key": "accountType",
                            "label": "صفة الحساب",
                            "icon": Icons.badge_outlined,
                            "readOnly": true,
                          },
                          {
                            "key": "about",
                            "label": "نبذة عنك",
                            "icon": Icons.info_outline,
                            "multiline": true,
                          },
                          {
                            "key": "specialization",
                            "label": "تفاصيل إضافية",
                            "icon": Icons.category,
                            "multiline": true,
                          },
                        ]),
                        buildSection([
                          {
                            "key": "experience",
                            "label": "سنوات الخبرة",
                            "icon": Icons.work_history,
                          },
                          {
                            "key": "languages",
                            "label": "لغات التواصل",
                            "icon": Icons.language,
                          },
                          {
                            "key": "location",
                            "label": "المدينة",
                            "icon": Icons.location_on_outlined,
                          },
                        ]),
                        buildSection([
                          {
                            "key": "details",
                            "label": "شرح تفصيلي",
                            "icon": Icons.notes,
                            "multiline": true,
                          },
                          {
                            "key": "qualification",
                            "label": "المؤهلات",
                            "icon": Icons.school,
                          },
                          {
                            "key": "website",
                            "label": "الموقع الإلكتروني",
                            "icon": Icons.link,
                          },
                          {
                            "key": "social",
                            "label": "روابط التواصل",
                            "icon": Icons.share_outlined,
                            "multiline": true,
                          },
                          {
                            "key": "phone",
                            "label": "واتساب",
                            "icon": Icons.phone_android,
                          },
                          {
                            "key": "keywords",
                            "label": "الكلمات المفتاحية (SEO)",
                            "icon": Icons.label_outline,
                            "multiline": true,
                          },
                        ]),
                      ],
                    ),
                  ),
      ),
    );
  }
}
