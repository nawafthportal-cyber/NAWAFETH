import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/content_service.dart';
import '../widgets/platform_top_bar.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _isLoading = true;
  String _heroTitle = 'منصة نوافذ';
  String _heroSubtitle = 'حلول تقنية مبتكرة تربط مزوّدي الخدمات بطالبيها';
  String _socialTitle = 'تواصل معنا';
  String _websiteLabel = 'الموقع الرسمي';
  String? _errorMessage;

  static const Map<String, Map<String, dynamic>> _sectionMeta = {
    'about': {
      'icon': Icons.info_outline_rounded,
      'tone': Color(0xFF6D5DF6),
      'kicker': 'نبذة',
    },
    'vision': {
      'icon': Icons.visibility_outlined,
      'tone': Color(0xFF8B5CF6),
      'kicker': 'رؤيتنا',
    },
    'goals': {
      'icon': Icons.track_changes_outlined,
      'tone': Color(0xFFD97706),
      'kicker': 'أهدافنا',
    },
    'values': {
      'icon': Icons.star_border_rounded,
      'tone': Color(0xFF0E8F72),
      'kicker': 'قيمنا',
    },
    'app': {
      'icon': Icons.phone_iphone_rounded,
      'tone': Color(0xFF334155),
      'kicker': 'عن التطبيق',
    },
  };

  static const Map<String, String> _defaultTitles = {
    "about": "من نحن",
    "vision": "رؤيتنا",
    "goals": "هدفنا",
    "values": "قيمنا",
    "app": "عن التطبيق",
  };

  static const Map<String, String> _defaultBodies = {
    "about":
        "منصة نوافذ للخدمات لتقنية المعلومات هي مؤسسة سعودية مقرها الرياض، متخصصة في تقديم منصة رقمية تجمع مزوّدي الخدمات مع طالبيها في مختلف المجالات.",
    "vision":
        "أن نكون المنصة الأولى في المملكة العربية السعودية التي تمكّن الأفراد والشركات من الوصول إلى الخدمات بسهولة وسرعة وشفافية.",
    "goals":
        "تسهيل التواصل بين مزوّدي الخدمات وطالبيها دون فرض رسوم على العملاء، مع توفير باقات اشتراك مخصصة لمزوّدي الخدمات تتيح لهم عرض خدماتهم بشكل أوسع.",
    "values":
        "الشفافية – الموثوقية – الجودة – الابتكار.\nكل ما نقوم به يستند إلى هذه القيم لتقديم تجربة مستخدم مثالية.",
    "app":
        "يتيح تطبيق منصة نوافذ للمستخدمين استعراض الخدمات والتواصل مع مزوّديها بسهولة. يمكنك أيضًا تقييم التطبيق ودعمه عبر المتاجر الرسمية.",
  };

  final Map<String, String> _titles = Map<String, String>.from(_defaultTitles);
  final Map<String, String> _bodies = Map<String, String>.from(_defaultBodies);
  String _androidStoreUrl = '';
  String _iosStoreUrl = '';
  String _websiteUrl = '';
  String _xUrl = '';
  String _instagramUrl = '';
  String _snapchatUrl = '';
  String _tiktokUrl = '';
  String _youtubeUrl = '';
  String _whatsappUrl = '';
  String _emailUrl = '';

  @override
  void initState() {
    super.initState();
    _loadPublicContent();
  }

  Future<void> _loadPublicContent() async {
    final result = await ContentService.fetchPublicContent();
    if (!mounted) return;

    if (result.isSuccess && result.dataAsMap != null) {
      final data = result.dataAsMap!;
      final blocks = (data['blocks'] as Map<String, dynamic>?) ?? {};
      final links = (data['links'] as Map<String, dynamic>?) ?? {};

      final aboutBlock = blocks['about_section_about'] as Map<String, dynamic>?;
      final visionBlock = blocks['about_section_vision'] as Map<String, dynamic>?;
      final goalsBlock = blocks['about_section_goals'] as Map<String, dynamic>?;
      final valuesBlock = blocks['about_section_values'] as Map<String, dynamic>?;
      final appBlock = blocks['about_section_app'] as Map<String, dynamic>?;

      setState(() {
        final heroTitle = (blocks['about_hero_title']?['title_ar'] as String?)?.trim() ?? '';
        final heroSubtitle = (blocks['about_hero_subtitle']?['title_ar'] as String?)?.trim() ?? '';
        final socialTitle = (blocks['about_social_title']?['title_ar'] as String?)?.trim() ?? '';
        final websiteLabel = (blocks['about_website_label']?['title_ar'] as String?)?.trim() ?? '';
        if (heroTitle.isNotEmpty) _heroTitle = heroTitle;
        if (heroSubtitle.isNotEmpty) _heroSubtitle = heroSubtitle;
        if (socialTitle.isNotEmpty) _socialTitle = socialTitle;
        if (websiteLabel.isNotEmpty) _websiteLabel = websiteLabel;
        if (aboutBlock != null) {
          _titles['about'] = (aboutBlock['title_ar'] as String?)?.trim().isNotEmpty == true
              ? aboutBlock['title_ar'] as String
              : _titles['about']!;
          _bodies['about'] = (aboutBlock['body_ar'] as String?)?.trim().isNotEmpty == true
              ? aboutBlock['body_ar'] as String
              : _bodies['about']!;
        }
        if (visionBlock != null) {
          _titles['vision'] = (visionBlock['title_ar'] as String?)?.trim().isNotEmpty == true
              ? visionBlock['title_ar'] as String
              : _titles['vision']!;
          _bodies['vision'] = (visionBlock['body_ar'] as String?)?.trim().isNotEmpty == true
              ? visionBlock['body_ar'] as String
              : _bodies['vision']!;
        }
        if (goalsBlock != null) {
          _titles['goals'] = (goalsBlock['title_ar'] as String?)?.trim().isNotEmpty == true
              ? goalsBlock['title_ar'] as String
              : _titles['goals']!;
          _bodies['goals'] = (goalsBlock['body_ar'] as String?)?.trim().isNotEmpty == true
              ? goalsBlock['body_ar'] as String
              : _bodies['goals']!;
        }
        if (valuesBlock != null) {
          _titles['values'] = (valuesBlock['title_ar'] as String?)?.trim().isNotEmpty == true
              ? valuesBlock['title_ar'] as String
              : _titles['values']!;
          _bodies['values'] = (valuesBlock['body_ar'] as String?)?.trim().isNotEmpty == true
              ? valuesBlock['body_ar'] as String
              : _bodies['values']!;
        }
        if (appBlock != null) {
          _titles['app'] = (appBlock['title_ar'] as String?)?.trim().isNotEmpty == true
              ? appBlock['title_ar'] as String
              : _titles['app']!;
          _bodies['app'] = (appBlock['body_ar'] as String?)?.trim().isNotEmpty == true
              ? appBlock['body_ar'] as String
              : _bodies['app']!;
        }

        _androidStoreUrl = (links['android_store'] as String? ?? '').trim();
        _iosStoreUrl = (links['ios_store'] as String? ?? '').trim();
        _websiteUrl = (links['website_url'] as String? ?? '').trim();
        _xUrl = (links['x_url'] as String? ?? '').trim();
        _instagramUrl = (links['instagram_url'] as String? ?? '').trim();
        _snapchatUrl = (links['snapchat_url'] as String? ?? '').trim();
        _tiktokUrl = (links['tiktok_url'] as String? ?? '').trim();
        _youtubeUrl = (links['youtube_url'] as String? ?? '').trim();
        _whatsappUrl = (links['whatsapp_url'] as String? ?? '').trim();
        _emailUrl = (links['email'] as String? ?? '').trim();
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = 'تعذر تحميل محتوى الصفحة الآن. يتم عرض المحتوى الافتراضي.';
      });
    }

    setState(() => _isLoading = false);
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرابط غير متوفر حالياً')),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }

  /// تطبيع رابط واتساب — لا يضيف prefix إذا بدأ بـ http
  String _normalizeWhatsapp(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('wa.me/')) return 'https://$v';
    // رقم هاتف فقط
    return 'https://wa.me/$v';
  }

  /// تطبيع بريد إلكتروني — لا يضيف mailto: إذا موجود مسبقاً
  String _normalizeEmail(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('mailto:')) return v;
    return 'mailto:$v';
  }

  Widget _buildInfoCard(String key, String title, String content) {
    final meta = _sectionMeta[key] ?? _sectionMeta['about']!;
    final tone = meta['tone'] as Color;
    final icon = meta['icon'] as IconData;
    final kicker = meta['kicker'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tone.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            kicker,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF22163F),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.8,
              color: Color(0xFF625B78),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkTile({
    required IconData icon,
    required String label,
    required String caption,
    required Color color,
    required String url,
    bool outlined = false,
  }) {
    return InkWell(
      onTap: () => _openExternalUrl(url),
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: outlined ? Colors.white : color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: outlined ? const Color(0x1A5F3DC4) : color,
          ),
          boxShadow: outlined
              ? []
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: outlined
                    ? color.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: outlined ? color : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: outlined ? const Color(0xFF22163F) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: outlined
                          ? const Color(0xFF6D6488)
                          : Colors.white.withValues(alpha: 0.84),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: outlined ? color : Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialTile({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
  }) {
    return InkWell(
      onTap: () => _openExternalUrl(url),
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2D1D57),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PlatformTopBar(
        pageLabel: 'حول منصة نوافذ',
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF34156F), Color(0xFF552BC0), Color(0xFF7A5AE8)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF34156F).withValues(alpha: 0.18),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'عن المنصة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.26),
                    ),
                  ),
                  child: const Icon(
                    Icons.dashboard_customize_rounded,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _heroTitle,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 30,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _heroSubtitle,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    height: 1.9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF3ECFF),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الوصول الرسمي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF3ECFF),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'روابط موثقة وهوية أوضح',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'اعرض الموقع الرسمي وروابط المتاجر ومنصات التواصل من واجهة واحدة منظمة.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.7,
                          color: Color(0xE6FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9A3412),
                ),
              ),
            ),
          ],

          const SizedBox(height: 22),

          const Text(
            'تعرف على نوافذ',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF22163F),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'محتوى مباشر وواضح بدل القوائم القابلة للطي، كما في واجهة الويب.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF625B78),
            ),
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            "about",
            _titles["about"] ?? _defaultTitles["about"]!,
            _bodies["about"] ?? _defaultBodies["about"]!,
          ),
          _buildInfoCard(
            "vision",
            _titles["vision"] ?? _defaultTitles["vision"]!,
            _bodies["vision"] ?? _defaultBodies["vision"]!,
          ),
          _buildInfoCard(
            "goals",
            _titles["goals"] ?? _defaultTitles["goals"]!,
            _bodies["goals"] ?? _defaultBodies["goals"]!,
          ),
          _buildInfoCard(
            "values",
            _titles["values"] ?? _defaultTitles["values"]!,
            _bodies["values"] ?? _defaultBodies["values"]!,
          ),
          _buildInfoCard(
            "app",
            _titles["app"] ?? _defaultTitles["app"]!,
            _bodies["app"] ?? _defaultBodies["app"]!,
          ),

          const SizedBox(height: 8),

          if (_androidStoreUrl.isNotEmpty || _iosStoreUrl.isNotEmpty || _websiteUrl.isNotEmpty) ...[
            const Text(
              'روابط المنصة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF22163F),
              ),
            ),
            const SizedBox(height: 12),
            if (_androidStoreUrl.isNotEmpty)
              _buildLinkTile(
                icon: FontAwesomeIcons.googlePlay,
                label: 'Google Play',
                caption: 'تطبيق Android',
                color: const Color(0xFF43218D),
                url: _androidStoreUrl,
              ),
            if (_androidStoreUrl.isNotEmpty &&
                (_iosStoreUrl.isNotEmpty || _websiteUrl.isNotEmpty))
              const SizedBox(height: 10),
            if (_iosStoreUrl.isNotEmpty)
              _buildLinkTile(
                icon: FontAwesomeIcons.appStoreIos,
                label: 'App Store',
                caption: 'تطبيق iPhone',
                color: const Color(0xFF5F3DC4),
                url: _iosStoreUrl,
              ),
            if (_iosStoreUrl.isNotEmpty && _websiteUrl.isNotEmpty)
              const SizedBox(height: 10),
            if (_websiteUrl.isNotEmpty)
              _buildLinkTile(
                icon: Icons.public_rounded,
                label: _websiteLabel,
                caption: 'زيارة موقع نوافذ',
                color: const Color(0xFF5F3DC4),
                url: _websiteUrl,
                outlined: true,
              ),
          ],

          if (_xUrl.isNotEmpty ||
              _instagramUrl.isNotEmpty ||
              _snapchatUrl.isNotEmpty ||
              _tiktokUrl.isNotEmpty ||
              _youtubeUrl.isNotEmpty ||
              _whatsappUrl.isNotEmpty ||
              _emailUrl.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _socialTitle,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF22163F),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_xUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: FontAwesomeIcons.xTwitter,
                    label: 'X',
                    url: _xUrl,
                    color: Colors.black,
                  ),
                if (_instagramUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: FontAwesomeIcons.instagram,
                    label: 'Instagram',
                    url: _instagramUrl,
                    color: const Color(0xFFC13584),
                  ),
                if (_snapchatUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: FontAwesomeIcons.snapchat,
                    label: 'Snapchat',
                    url: _snapchatUrl,
                    color: const Color(0xFFFACC15),
                  ),
                if (_tiktokUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: FontAwesomeIcons.tiktok,
                    label: 'TikTok',
                    url: _tiktokUrl,
                    color: const Color(0xFF111827),
                  ),
                if (_youtubeUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: FontAwesomeIcons.youtube,
                    label: 'YouTube',
                    url: _youtubeUrl,
                    color: const Color(0xFFDC2626),
                  ),
                if (_whatsappUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: FontAwesomeIcons.whatsapp,
                    label: 'واتساب',
                    url: _normalizeWhatsapp(_whatsappUrl),
                    color: const Color(0xFF25D366),
                  ),
                if (_emailUrl.isNotEmpty)
                  _buildSocialTile(
                    icon: Icons.email_outlined,
                    label: 'البريد',
                    url: _normalizeEmail(_emailUrl),
                    color: const Color(0xFF5F3DC4),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x1A5F3DC4)),
            ),
            child: Text(
              'مؤسسة نوافذ للخدمات لتقنية المعلومات\nالمملكة العربية السعودية - الرياض',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF625B78),
                height: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
