import 'package:flutter/material.dart';
import 'package:nawafeth/models/provider_profile_model.dart';
import 'package:nawafeth/models/user_profile.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/screens/registration/steps/contact_info_step.dart';
import 'package:nawafeth/screens/registration/steps/content_step.dart';
import 'package:nawafeth/screens/registration/steps/language_location_step.dart';
import 'package:nawafeth/screens/registration/steps/seo_step.dart';
import 'package:nawafeth/screens/registration/steps/service_details_step.dart';
import 'package:nawafeth/widgets/platform_top_bar.dart';

import '../../constants/colors.dart';

class ProviderProfileCompletionScreen extends StatefulWidget {
  const ProviderProfileCompletionScreen({super.key});

  @override
  State<ProviderProfileCompletionScreen> createState() =>
      _ProviderProfileCompletionScreenState();
}

class _ProviderProfileCompletionScreenState
    extends State<ProviderProfileCompletionScreen> {
  ProviderProfileModel? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final result = await ProfileService.fetchProviderProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      setState(() {
        _profile = result.data;
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = result.error ?? 'تعذر جلب بيانات الملف';
    });
  }

  double get _completionPercent =>
      _profile?.profileCompletion ?? ProviderProfileModel.baseCompletionWeight;

  int _sectionPercent() =>
      (ProviderProfileModel.optionalSectionWeight * 100).round();

  bool _isSectionComplete(String id) {
    final profile = _profile;
    if (profile == null) return false;

    switch (id) {
      case 'service_details':
        return profile.isServiceDetailsComplete;
      case 'additional':
        return profile.isAdditionalDetailsComplete;
      case 'contact_full':
        return profile.isContactInfoComplete;
      case 'lang_loc':
        return profile.isLanguageLocationComplete;
      case 'content':
        return profile.isContentComplete;
      case 'seo':
        return profile.isSeoComplete;
      default:
        return false;
    }
  }

  Future<void> _openSection(String id) async {
    bool? result;

    switch (id) {
      case 'basic':
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => _BasicInfoDetailsScreen(initialProfile: _profile),
          ),
        );
        await _loadProfile(silent: true);
        return;
      case 'service_details':
        result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => _SingleStepWrapper(
              title: 'تفاصيل الخدمة',
              child: ServiceDetailsStep(
                onBack: () => Navigator.pop(context, false),
                onNext: () => Navigator.pop(context, true),
              ),
            ),
          ),
        );
        break;
      case 'contact_full':
        result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ContactInfoStep(
              isInitialRegistration: false,
              isFinalStep: false,
              onBack: () => Navigator.pop(context, false),
              onNext: () => Navigator.pop(context, true),
            ),
          ),
        );
        break;
      case 'lang_loc':
        result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LanguageLocationStep(
              onBack: () => Navigator.pop(context, false),
              onNext: () => Navigator.pop(context, true),
            ),
          ),
        );
        break;
      case 'content':
        result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ContentStep(
              onBack: () => Navigator.pop(context, false),
              onNext: () => Navigator.pop(context, true),
            ),
          ),
        );
        break;
      case 'seo':
        result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => SeoStep(
              onBack: () => Navigator.pop(context, false),
              onNext: () => Navigator.pop(context, true),
            ),
          ),
        );
        break;
      default:
        result = false;
    }

    if (!mounted) return;
    await _loadProfile(silent: true);

    if (result == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_completionPercent * 100).round();
    final sectionPercent = _sectionPercent();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: const PlatformTopBar(
          pageLabel: 'إكمال الملف التعريفي',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.deepPurple),
              )
            : (_errorMessage != null && _profile == null)
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: () => _loadProfile(silent: true),
                    color: AppColors.deepPurple,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        _progressCard(percent: percent),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 10),
                          _inlineError(),
                        ],
                        const SizedBox(height: 10),
                        _basicSectionTile(),
                        const SizedBox(height: 4),
                        _sectionTile(
                          id: 'service_details',
                          title: 'تفاصيل الخدمة',
                          subtitle: 'اسم الخدمة ووصف مختصر.',
                          extra: 'يمثل حوالي $sectionPercent٪ من اكتمال الملف.',
                          icon: Icons.home_repair_service_outlined,
                          color: Colors.indigo,
                        ),
                        _sectionTile(
                          id: 'additional',
                          title: 'معلومات إضافية عنك وخدماتك',
                          subtitle: 'تفاصيل موسّعة عن خدماتك ومؤهلاتك وخبراتك.',
                          extra: 'يمثل حوالي $sectionPercent٪ من اكتمال الملف.',
                          icon: Icons.notes_outlined,
                          color: Colors.teal,
                        ),
                        _sectionTile(
                          id: 'contact_full',
                          title: 'معلومات التواصل الكاملة',
                          subtitle:
                              'روابط التواصل الاجتماعي، واتساب، موقع إلكتروني.',
                          extra: 'يمثل حوالي $sectionPercent٪ من اكتمال الملف.',
                          icon: Icons.call_outlined,
                          color: Colors.blue,
                        ),
                        _sectionTile(
                          id: 'lang_loc',
                          title: 'اللغة ونطاق الخدمة',
                          subtitle: 'اللغات التي تجيدها ونطاق تقديم خدماتك.',
                          extra: 'يمثل حوالي $sectionPercent٪ من اكتمال الملف.',
                          icon: Icons.language_outlined,
                          color: Colors.orange,
                        ),
                        _sectionTile(
                          id: 'content',
                          title: 'محتوى أعمالك (Portfolio)',
                          subtitle: 'أضف صوراً أو نماذج من أعمالك السابقة.',
                          extra: 'يمثل حوالي $sectionPercent٪ من اكتمال الملف.',
                          icon: Icons.image_outlined,
                          color: Colors.purple,
                        ),
                        _sectionTile(
                          id: 'seo',
                          title: 'SEO والكلمات المفتاحية',
                          subtitle: 'تعريف محركات البحث بنوعية خدمتك.',
                          extra: 'يمثل حوالي $sectionPercent٪ من اكتمال الملف.',
                          icon: Icons.search,
                          color: Colors.blueGrey,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _progressCard({required int percent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'نسبة اكتمال الملف',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: LinearProgressIndicator(
              value: _completionPercent,
              minHeight: 7,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.deepPurple,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$percent%',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '30٪ من التسجيل الأساسي، والباقي من إكمال الأقسام أدناه.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inlineError() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
                backgroundColor: AppColors.deepPurple,
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

  Widget _basicSectionTile() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.deepPurple.withValues(alpha: 0.4),
          width: 1.4,
        ),
      ),
      child: ListTile(
        onTap: () => _openSection('basic'),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          child: Icon(
            Icons.person_pin_circle_outlined,
            color: AppColors.deepPurple,
          ),
        ),
        title: const Text(
          'بيانات التسجيل الأساسية',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: const Text(
          'المعلومات الأساسية + تصنيف الاختصاص + بيانات التواصل الأساسية.\nتمت تعبئتها أثناء التسجيل.',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            color: Colors.black54,
            height: 1.4,
          ),
        ),
        trailing: const Icon(Icons.check_circle, color: Colors.green, size: 22),
      ),
    );
  }

  Widget _sectionTile({
    required String id,
    required String title,
    required String subtitle,
    required String extra,
    required IconData icon,
    required Color color,
  }) {
    final done = _isSectionComplete(id);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: done ? color.withValues(alpha: 0.4) : Colors.grey.shade200,
          width: done ? 1.4 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => _openSection(id),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.08),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              extra,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        trailing: done
            ? const Icon(Icons.check_circle, color: Colors.green, size: 22)
            : const Icon(Icons.chevron_left, color: Colors.black45),
      ),
    );
  }
}

class _BasicInfoDetailsScreen extends StatefulWidget {
  final ProviderProfileModel? initialProfile;

  const _BasicInfoDetailsScreen({this.initialProfile});

  @override
  State<_BasicInfoDetailsScreen> createState() => _BasicInfoDetailsScreenState();
}

class _BasicInfoDetailsScreenState extends State<_BasicInfoDetailsScreen> {
  ProviderProfileModel? _providerProfile;
  UserProfile? _userProfile;
  List<Map<String, dynamic>> _myServices = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _providerProfile = widget.initialProfile;
    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final results = await Future.wait([
      ProfileService.fetchProviderProfile(),
      ProfileService.fetchMyProfile(),
      ApiClient.get('/api/providers/me/services/'),
    ]);
    if (!mounted) return;

    final providerResult = results[0] as ProfileResult<ProviderProfileModel>;
    final meResult = results[1] as ProfileResult<UserProfile>;
    final servicesResp = results[2] as ApiResponse;

    if (providerResult.isSuccess && providerResult.data != null) {
      _providerProfile = providerResult.data;
    }
    if (meResult.isSuccess && meResult.data != null) {
      _userProfile = meResult.data;
    }
    if (servicesResp.isSuccess) {
      _myServices = _parseList(servicesResp.data);
    } else {
      _myServices = [];
    }

    setState(() {
      _isLoading = false;
      if (_providerProfile == null) {
        _errorMessage = providerResult.error ?? 'تعذر جلب بيانات التسجيل الأساسية';
      } else {
        _errorMessage = null;
      }
    });
  }

  List<Map<String, dynamic>> _parseList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map && data['results'] is List) {
      final list = data['results'] as List;
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
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
        return type.trim();
    }
  }

  List<String> _uniqueNonEmpty(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) continue;
      if (seen.add(clean)) {
        result.add(clean);
      }
    }
    return result;
  }

  String _nameAccountValue() {
    final providerName = (_providerProfile?.displayName ?? '').trim();
    final usernameRaw = (_userProfile?.username ?? '').trim();
    final username = usernameRaw.isEmpty
        ? ''
        : (usernameRaw.startsWith('@') ? usernameRaw : '@$usernameRaw');

    if (providerName.isEmpty && username.isEmpty) return 'غير متوفر';
    if (providerName.isNotEmpty && username.isNotEmpty) {
      return '$providerName\n$username';
    }
    return providerName.isNotEmpty ? providerName : username;
  }

  String _specializationValue() {
    final providerType = _providerTypeLabel(_providerProfile?.providerType ?? '');
    final categories = _uniqueNonEmpty(_myServices.map((service) {
      final sub = service['subcategory'];
      if (sub is Map) {
        return (sub['category_name'] ?? '').toString();
      }
      return '';
    }));
    final subcategories = _uniqueNonEmpty(_myServices.map((service) {
      final sub = service['subcategory'];
      if (sub is Map) {
        return (sub['name'] ?? '').toString();
      }
      return '';
    }));

    final lines = <String>[];
    if (providerType.isNotEmpty) lines.add('نوع الحساب: $providerType');
    if (categories.isNotEmpty) lines.add('التصنيف: ${categories.join('، ')}');
    if (subcategories.isNotEmpty) {
      lines.add('التخصصات: ${subcategories.join('، ')}');
    }

    if (lines.isEmpty) return 'غير متوفر';
    return lines.join('\n');
  }

  String _contactValue() {
    final phone = (_userProfile?.phone ?? '').trim();
    final whatsapp = (_providerProfile?.whatsapp ?? '').trim();
    final city = (_providerProfile?.locationDisplay ?? '').trim();

    final lines = <String>[];
    if (phone.isNotEmpty) lines.add('الجوال: $phone');
    if (whatsapp.isNotEmpty) lines.add('واتساب: $whatsapp');
    if (city.isNotEmpty) lines.add('المدينة: $city');
    return lines.isEmpty ? 'غير متوفر' : lines.join('\n');
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          color: Colors.black54,
          height: 1.45,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: const PlatformTopBar(
          overlay: true,
          pageLabel: 'بيانات التسجيل الأساسية',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.deepPurple),
              )
            : RefreshIndicator(
                onRefresh: () => _loadData(silent: true),
                color: AppColors.deepPurple,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'هذه البيانات تم إدخالها أثناء التسجيل الأولي.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _infoTile(
                      icon: Icons.person,
                      title: 'الاسم / اسم الحساب',
                      value: _nameAccountValue(),
                    ),
                    _infoTile(
                      icon: Icons.category_outlined,
                      title: 'تصنيف الاختصاص',
                      value: _specializationValue(),
                    ),
                    _infoTile(
                      icon: Icons.phone,
                      title: 'بيانات التواصل الأساسية',
                      value: _contactValue(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SingleStepWrapper extends StatelessWidget {
  final String title;
  final Widget child;

  const _SingleStepWrapper({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PlatformTopBar(
        pageLabel: title,
        showBackButton: true,
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: child,
    );
  }
}
