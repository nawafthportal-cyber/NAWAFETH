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
  String _whatsappUrl = '';
  String _emailUrl = '';

  /// 🔹 التحكم بفتح/إغلاق الكروت
  final Map<String, bool> _expanded = {
    "about": false,
    "vision": false,
    "goals": false,
    "values": false,
    "app": false,
  };

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
        _whatsappUrl = (links['whatsapp_url'] as String? ?? '').trim();
        _emailUrl = (links['email'] as String? ?? '').trim();
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

  /// 🔹 بناء الكرت القابل للتوسيع
  Widget _buildExpandableCard(
    String key,
    String title,
    String content,
    IconData icon,
  ) {
    final isExpanded = _expanded[key] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          ListTile(
              leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
              child: Icon(icon, color: Colors.deepPurple, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.deepPurple,
            ),
            onTap: () {
              setState(() {
                _expanded[key] = !isExpanded;
              });
            },
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                content,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ),
            crossFadeState:
                isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  /// 🔹 أيقونة تواصل اجتماعي
  Widget _buildSocialIcon(IconData icon, String tooltip, String url, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: () => _openExternalUrl(url),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      ),
    );
  }

  /// 🔹 زر متجر أنيق
  Widget _buildStoreButton(IconData icon, String label, Color color, String url) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => _openExternalUrl(url),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
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
          // ✅ هيدر أنيق
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple, Colors.deepPurple.shade400],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.window_rounded, size: 42, color: Colors.white),
                const SizedBox(height: 10),
                Text(
                  _heroTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _heroSubtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // ✅ الكروت القابلة للتوسيع
          _buildExpandableCard(
            "about",
            _titles["about"] ?? _defaultTitles["about"]!,
            _bodies["about"] ?? _defaultBodies["about"]!,
            Icons.info_outline,
          ),
          _buildExpandableCard(
            "vision",
            _titles["vision"] ?? _defaultTitles["vision"]!,
            _bodies["vision"] ?? _defaultBodies["vision"]!,
            Icons.visibility_outlined,
          ),
          _buildExpandableCard(
            "goals",
            _titles["goals"] ?? _defaultTitles["goals"]!,
            _bodies["goals"] ?? _defaultBodies["goals"]!,
            Icons.track_changes_outlined,
          ),
          _buildExpandableCard(
            "values",
            _titles["values"] ?? _defaultTitles["values"]!,
            _bodies["values"] ?? _defaultBodies["values"]!,
            Icons.star_border_outlined,
          ),
          _buildExpandableCard(
            "app",
            _titles["app"] ?? _defaultTitles["app"]!,
            _bodies["app"] ?? _defaultBodies["app"]!,
            Icons.mobile_screen_share_outlined,
          ),

          const SizedBox(height: 12),

          // ✅ أزرار المتاجر
          Row(
            children: [
              _buildStoreButton(
                FontAwesomeIcons.googlePlay,
                "Google Play",
                Colors.green,
                _androidStoreUrl,
              ),
              _buildStoreButton(
                FontAwesomeIcons.appStoreIos,
                "App Store",
                Colors.blue,
                _iosStoreUrl,
              ),
            ],
          ),

          if (_websiteUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openExternalUrl(_websiteUrl),
                icon: const Icon(Icons.public),
                    label: Text(_websiteLabel),
              ),
            ),
          ],

          // ✅ روابط التواصل الاجتماعي
          if (_xUrl.isNotEmpty || _whatsappUrl.isNotEmpty || _emailUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                _socialTitle,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_xUrl.isNotEmpty)
                  _buildSocialIcon(
                    FontAwesomeIcons.xTwitter,
                    'X',
                    _xUrl,
                    Colors.black,
                  ),
                if (_whatsappUrl.isNotEmpty)
                  _buildSocialIcon(
                    FontAwesomeIcons.whatsapp,
                    'واتساب',
                    _normalizeWhatsapp(_whatsappUrl),
                    const Color(0xFF25D366),
                  ),
                if (_emailUrl.isNotEmpty)
                  _buildSocialIcon(
                    Icons.email_outlined,
                    'البريد',
                    _normalizeEmail(_emailUrl),
                    Colors.deepPurple,
                  ),
              ],
            ),
          ],

          const SizedBox(height: 30),

          // ✅ بيانات ختامية
          Center(
            child: Text(
              "مؤسسة نوافذ للخدمات لتقنية المعلومات\n"
              "📍 المملكة العربية السعودية - الرياض",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.grey[700],
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
