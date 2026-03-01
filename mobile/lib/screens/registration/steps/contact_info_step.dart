import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/utils/debounced_save_runner.dart';
import 'package:nawafeth/models/user_profile.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactInfoStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  /// إذا كانت هذه الشاشة تُستخدم في التسجيل الأولي (حقول أساسية فقط)
  final bool isInitialRegistration;

  /// تستخدم لتغيير نص الزر إلى "إنهاء التسجيل"
  final bool isFinalStep;
  
  final Function(double)? onValidationChanged;

  /// بيانات المستخدم المسجلة مسبقًا للتعبئة التلقائية
  final UserProfile? userProfile;

  /// خريطة بيانات التسجيل المشتركة
  final Map<String, dynamic>? registrationData;

  const ContactInfoStep({
    super.key,
    required this.onNext,
    required this.onBack,
    this.isInitialRegistration = false,
    this.isFinalStep = false,
    this.onValidationChanged,
    this.userProfile,
    this.registrationData,
  });

  @override
  State<ContactInfoStep> createState() => _ContactInfoStepState();
}

class _ContactInfoStepState extends State<ContactInfoStep> {
  // Controllers
  final websiteController = TextEditingController();
  final phoneController = TextEditingController();
  final whatsappController = TextEditingController();
  final mapLocationController = TextEditingController();
  final socialControllers = List.generate(9, (_) => TextEditingController());
  final DebouncedSaveRunner _autoSaveRunner = DebouncedSaveRunner();

  // Logo
  final ImagePicker _picker = ImagePicker();
  File? _logoFile;

  // Accordion state (للوضع الكامل فقط)
  Map<String, bool> expanded = {
    "website": false,
    "social": false,
    "whatsapp": false,
    "phone": false,
    "map": false,
  };

  final socialIcons = [
    FontAwesomeIcons.linkedin,
    FontAwesomeIcons.facebook,
    FontAwesomeIcons.youtube,
    FontAwesomeIcons.instagram,
    FontAwesomeIcons.xTwitter,
    FontAwesomeIcons.snapchatGhost,
    FontAwesomeIcons.pinterest,
    FontAwesomeIcons.tiktok,
    FontAwesomeIcons.behance,
  ];

  final socialLabels = [
    "LinkedIn",
    "Facebook",
    "YouTube",
    "Instagram",
    "X (Twitter)",
    "Snapchat",
    "Pinterest",
    "TikTok",
    "Behance",
  ];

  bool _isLoadingProfile = false;
  bool _isSavingProfile = false;
  bool _isProfileReady = false;
  String? _saveError;

  Future<void> _pickLocation() async {
    final lat = 24.7136;
    final lng = 46.6753;
    final appUri = Uri.parse("geo:$lat,$lng?q=$lat,$lng");
    final webUri = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }

      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تعذر فتح خرائط Google حاليًا.")),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تعذر فتح خرائط Google حاليًا.")),
    );
  }

  @override
  void initState() {
    super.initState();
    phoneController.addListener(_onPhoneChanged);
    whatsappController.addListener(_onWhatsappChanged);
    websiteController.addListener(_onProfileFieldChanged);
    for (final controller in socialControllers) {
      controller.addListener(_onProfileFieldChanged);
    }

    if (widget.isInitialRegistration) {
      _isProfileReady = true;
      // تعبئة تلقائية من بيانات المستخدم المسجلة
      _prefillFromUserProfile();
    } else {
      _loadProviderProfile();
    }

    // تأجيل الاستدعاء الأول حتى بعد اكتمال البناء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateForm();
    });
  }

  void _onPhoneChanged() {
    _validateForm();
  }

  void _onWhatsappChanged() {
    _validateForm();
    _queueAutoSave();
  }

  void _onProfileFieldChanged() {
    _queueAutoSave();
  }

  @override
  void didUpdateWidget(covariant ContactInfoStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile == null && widget.userProfile != null) {
      _prefillFromUserProfile();
      _validateForm();
    }
  }

  /// سحب بيانات المستخدم المسجلة وتعبئتها في الحقول (قابلة للتعديل)
  void _prefillFromUserProfile() {
    final profile = widget.userProfile;
    if (profile == null) return;

    // تعبئة رقم الهاتف
    if (profile.phone != null && profile.phone!.isNotEmpty && phoneController.text.isEmpty) {
      phoneController.text = profile.phone!;
    }

    // تعبئة الواتساب بنفس رقم الهاتف إذا متوفر
    if (profile.phone != null && profile.phone!.isNotEmpty && whatsappController.text.isEmpty) {
      // تحويل الرقم لصيغة wa.me
      final cleanPhone = profile.phone!.replaceAll(RegExp(r'[^0-9+]'), '');
      whatsappController.text = 'https://wa.me/$cleanPhone';
    }
  }

  Future<void> _loadProviderProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoadingProfile = true;
      _saveError = null;
    });

    final result = await ProfileService.fetchProviderProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      final profile = result.data!;
      final socialLinks = profile.socialLinks
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();

      setState(() {
        websiteController.text = profile.website ?? '';
        whatsappController.text = profile.whatsapp ?? '';
        for (int i = 0; i < socialControllers.length; i++) {
          socialControllers[i].text = i < socialLinks.length ? socialLinks[i] : '';
        }
        _isLoadingProfile = false;
        _isProfileReady = true;
        _saveError = null;
      });
      _validateForm();
      return;
    }

    setState(() {
      _isLoadingProfile = false;
      _isProfileReady = true;
      _saveError = result.error ?? 'تعذر تحميل بيانات التواصل';
    });
  }

  void _queueAutoSave() {
    if (widget.isInitialRegistration || !_isProfileReady) return;
    _autoSaveRunner.schedule(_saveProviderProfile);
  }

  Future<void> _saveProviderProfile() async {
    if (widget.isInitialRegistration) return;

    final payload = <String, dynamic>{
      'website': websiteController.text.trim(),
      'whatsapp': whatsappController.text.trim(),
      'social_links': socialControllers
          .map((c) => c.text.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
    };

    if (!mounted) return;
    setState(() {
      _isSavingProfile = true;
    });

    final result = await ProfileService.updateProviderProfile(payload);
    if (!mounted) return;

    setState(() {
      _isSavingProfile = false;
      _saveError = result.isSuccess ? null : (result.error ?? 'فشل الحفظ');
    });
  }

  void _validateForm() {
    // حساب النسبة بناءً على الحقول المملوءة
    double completionPercent = 0.0;
    
    // رقم الهاتف الأساسي (60% من الصفحة)
    if (phoneController.text.trim().isNotEmpty) {
      completionPercent += 0.6;
    }
    
    // واتساب (40% من الصفحة - اختياري)
    if (whatsappController.text.trim().isNotEmpty) {
      completionPercent += 0.4;
    }
    
    widget.onValidationChanged?.call(completionPercent);
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (picked != null) {
        setState(() {
          _logoFile = File(picked.path);
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تعذر اختيار الشعار حاليًا.")),
      );
    }
  }

  @override
  void dispose() {
    phoneController.removeListener(_onPhoneChanged);
    whatsappController.removeListener(_onWhatsappChanged);
    websiteController.removeListener(_onProfileFieldChanged);
    for (final c in socialControllers) {
      c.removeListener(_onProfileFieldChanged);
    }
    websiteController.dispose();
    phoneController.dispose();
    whatsappController.dispose();
    mapLocationController.dispose();
    for (final c in socialControllers) {
      c.dispose();
    }
    _autoSaveRunner.dispose();
    super.dispose();
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    final isInitial = widget.isInitialRegistration;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildSaveStatus(),
                  const SizedBox(height: 16),
                  _buildLogoHeader(),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      child: (!isInitial && _isLoadingProfile)
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.deepPurple,
                                ),
                              ),
                            )
                          : (isInitial
                              ? _buildInitialForm()
                              : _buildFullAccordion()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- HEADER ----------------

  Widget _buildHeader() {
    final subtitle =
        widget.isInitialRegistration
            ? "أدخل بيانات التواصل الأساسية ليتمكن العملاء من الوصول إليك."
            : "حدّث بيانات تواصلك لتسهل على العملاء الوصول إليك عبر القنوات المناسبة لهم.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "معلومات التواصل",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontFamily: "Cairo",
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: "Cairo",
            color: Colors.black54,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveStatus() {
    if (widget.isInitialRegistration) return const SizedBox.shrink();

    if (_isSavingProfile) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'جاري الحفظ التلقائي...',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black54),
          ),
        ],
      );
    }

    if (_saveError != null) {
      return Text(
        _saveError!,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          color: Colors.redAccent,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ---------------- LOGO HEADER ----------------

  Widget _buildLogoHeader() {
    return Column(
      children: [
        Row(
          children: [
            // دائرة الشعار
            CircleAvatar(
              radius: 34,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: _logoFile != null ? FileImage(_logoFile!) : null,
              child:
                  _logoFile == null
                      ? const Icon(Icons.person, size: 34, color: Colors.white)
                      : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "شعار حسابك",
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "يُعرض الشعار في ملفك التعريفي وفي نتائج البحث. اختر صورة واضحة تمثل نشاطك.",
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 11.5,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text(
              "تعديل الشعار",
              style: TextStyle(fontFamily: "Cairo"),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepPurple,
              side: const BorderSide(color: Colors.deepPurple),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- INITIAL FORM (بسيط) ----------------

  Widget _buildInitialForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoTip(
          icon: Icons.info_outline,
          text:
              "هذه البيانات أساسية لإنشاء حسابك، يمكنك إضافة مزيد من وسائل التواصل لاحقًا من خلال إكمال الملف التعريفي.",
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: "رقم الهاتف الأساسي",
          icon: Icons.phone_android,
          child: _styledField(
            controller: phoneController,
            hint: "+9665xxxxxxxx",
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
        ),
        _sectionCard(
          title: "واتساب (اختياري)",
          icon: FontAwesomeIcons.whatsapp,
          child: _styledField(
            controller: whatsappController,
            hint: "https://wa.me/رقمك",
            icon: FontAwesomeIcons.whatsapp,
            keyboardType: TextInputType.url,
          ),
        ),
      ],
    );
  }

  // ---------------- FULL ACCORDION FORM ----------------

  Widget _buildFullAccordion() {
    return Column(
      children: [
        _infoTip(
          icon: Icons.info_outline,
          text:
              "يمكنك التحكم في كل وسيلة تواصل بشكل مستقل من خلال الكروت أدناه. اضغط على أي كرت لعرض حقوله.",
        ),
        const SizedBox(height: 14),

        // موقع إلكتروني
        _accordionCard(
          id: "website",
          icon: Icons.language,
          title: "الموقع الإلكتروني",
          child: _styledField(
            controller: websiteController,
            hint: "https://example.com",
            icon: Icons.link,
            keyboardType: TextInputType.url,
          ),
        ),

        // وسائل التواصل
        _accordionCard(
          id: "social",
          icon: Icons.share_outlined,
          title: "وسائل التواصل الاجتماعي",
          child: Column(
            children: List.generate(
              socialControllers.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _styledField(
                  controller: socialControllers[i],
                  hint: "رابط ${socialLabels[i]}",
                  icon: socialIcons[i],
                  keyboardType: TextInputType.url,
                ),
              ),
            ),
          ),
        ),

        // واتساب
        _accordionCard(
          id: "whatsapp",
          icon: FontAwesomeIcons.whatsapp,
          title: "واتساب",
          child: _styledField(
            controller: whatsappController,
            hint: "https://wa.me/رقمك",
            icon: FontAwesomeIcons.whatsapp,
            keyboardType: TextInputType.url,
          ),
        ),

        // رقم الهاتف
        _accordionCard(
          id: "phone",
          icon: Icons.phone,
          title: "رقم الهاتف",
          child: _styledField(
            controller: phoneController,
            hint: "+9665xxxxxxxx",
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
        ),

        // موقعي على الخريطة
        _accordionCard(
          id: "map",
          icon: Icons.location_on_outlined,
          title: "موقعي على الخريطة",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _styledField(
                      controller: mapLocationController,
                      hint: "رابط موقعي على الخريطة",
                      icon: FontAwesomeIcons.mapLocationDot,
                      keyboardType: TextInputType.url,
                      readOnly: true,
                      onTap: _pickLocation,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _pickLocation,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text(
                      "تحديد",
                      style: TextStyle(fontFamily: "Cairo"),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "اضغط على حقل الموقع أو زر \"تحديد\" لفتح خرائط Google وتحديد موقعك.",
                style: TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 11.5,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- ACCORDION CARD ----------------

  Widget _accordionCard({
    required String id,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final isOpen = expanded[id] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color:
              isOpen
                  ? Colors.deepPurple.withOpacity(0.4)
                  : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.withOpacity(0.1),
              child: Icon(icon, color: Colors.deepPurple),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Icon(
              isOpen ? Icons.expand_less : Icons.expand_more,
              color: Colors.deepPurple,
            ),
            onTap: () {
              setState(() => expanded[id] = !isOpen);
            },
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
        ],
      ),
    );
  }

  // ---------------- SIMPLE SECTION CARD (للنموذج البسيط) ----------------

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.deepPurple.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.deepPurple, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // ---------------- INFO TIP ----------------

  Widget _infoTip({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.deepPurple, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 11.5,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- INPUT FIELD ----------------

  Widget _styledField({
    required TextEditingController controller,
    IconData? icon,
    String? hint,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(fontFamily: "Cairo", fontSize: 13.5),
      decoration: InputDecoration(
        prefixIcon: icon != null ? Icon(icon, color: Colors.deepPurple) : null,
        hintText: hint,
        hintStyle: const TextStyle(
          color: Colors.grey,
          fontFamily: "Cairo",
          fontSize: 13,
        ),
        filled: true,
        fillColor: const Color(0xFFF7F5FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.deepPurple),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Colors.deepPurple, width: 1.4),
        ),
      ),
    );
  }

  // ---------------- ACTION BUTTONS ----------------

  Widget _buildActionButtons() {
    final primaryLabel = widget.isFinalStep ? "إنهاء التسجيل" : "التالي";

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              if (!widget.isInitialRegistration) {
                await _autoSaveRunner.flush();
              }
              widget.onBack();
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text("السابق", style: TextStyle(fontFamily: "Cairo")),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepPurple,
              side: const BorderSide(color: Colors.deepPurple),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (!widget.isInitialRegistration && _isLoadingProfile)
                ? null
                : () async {
                    // حفظ بيانات التواصل في خريطة التسجيل
                    if (widget.isInitialRegistration) {
                      widget.registrationData?['whatsapp'] = whatsappController.text.trim();
                    }
                    if (!widget.isInitialRegistration) {
                      await _autoSaveRunner.flush();
                    }
                    widget.onNext();
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              primaryLabel,
              style: const TextStyle(fontFamily: "Cairo"),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
