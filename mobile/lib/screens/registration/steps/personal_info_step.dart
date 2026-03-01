import 'package:flutter/material.dart';
import '../../../models/user_profile.dart';

class PersonalInfoStep extends StatefulWidget {
  final VoidCallback onNext;
  final Function(double)? onValidationChanged;
  final UserProfile? userProfile;
  final Map<String, dynamic>? registrationData;

  const PersonalInfoStep({
    super.key,
    required this.onNext,
    this.onValidationChanged,
    this.userProfile,
    this.registrationData,
  });

  @override
  State<PersonalInfoStep> createState() => _PersonalInfoStepState();
}

class _PersonalInfoStepState extends State<PersonalInfoStep> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController engNameController = TextEditingController();
  final TextEditingController bioController = TextEditingController();

  String accountType = "فرد";

  static const TextStyle labelStyle = TextStyle(
    fontFamily: 'Cairo',
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Cairo'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // تعبئة تلقائية من بيانات المستخدم المسجلة مسبقًا
    _prefillFromUserProfile();
    nameController.addListener(_validateForm);
    engNameController.addListener(_validateForm);
    bioController.addListener(_validateForm);
    // تأجيل الاستدعاء الأول حتى بعد اكتمال البناء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateForm();
    });
  }

  @override
  void didUpdateWidget(covariant PersonalInfoStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إذا وصلت بيانات المستخدم متأخرة، نعبئ الحقول
    if (oldWidget.userProfile == null && widget.userProfile != null) {
      _prefillFromUserProfile();
      _validateForm();
    }
  }

  /// سحب بيانات المستخدم المسجلة وتعبئتها في الحقول (قابلة للتعديل)
  void _prefillFromUserProfile() {
    final profile = widget.userProfile;
    if (profile == null) return;

    // تعبئة الاسم الكامل من first_name + last_name
    final fullName = [profile.firstName, profile.lastName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    if (fullName.isNotEmpty && nameController.text.isEmpty) {
      nameController.text = fullName;
    }
  }

  void _validateForm() {
    // حساب النسبة بناءً على الحقول المملوءة
    double completionPercent = 0.0;
    
    // الاسم الكامل (40% من الصفحة)
    if (nameController.text.trim().isNotEmpty) {
      completionPercent += 0.4;
    }
    
    // الاسم بالإنجليزي (20% من الصفحة - اختياري)
    if (engNameController.text.trim().isNotEmpty) {
      completionPercent += 0.2;
    }
    
    // النبذة (40% من الصفحة)
    if (bioController.text.trim().isNotEmpty) {
      completionPercent += 0.4;
    }
    
    widget.onValidationChanged?.call(completionPercent);
  }

  @override
  void dispose() {
    nameController.dispose();
    engNameController.dispose();
    bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text("الاسم الكامل للحساب", style: labelStyle),
          const SizedBox(height: 8),
          TextField(
            controller: nameController,
            style: const TextStyle(fontFamily: 'Cairo'),
            decoration: _fieldDecoration("أدخل اسمك الكامل"),
          ),

          const SizedBox(height: 16),
          const Text("الاسم الكامل بالإنجليزي (اختياري)", style: labelStyle),
          const SizedBox(height: 8),
          TextField(
            controller: engNameController,
            style: const TextStyle(fontFamily: 'Cairo'),
            decoration: _fieldDecoration("Full name in English (optional)"),
          ),

          const SizedBox(height: 16),
          const Text("صفة الحساب", style: labelStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: const Text(
                    "فرد",
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  value: "فرد",
                  groupValue: accountType,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => accountType = val);
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text(
                    "منشأة",
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  value: "منشأة",
                  groupValue: accountType,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => accountType = val);
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Text("نبذة عنك كمقدم خدمة", style: labelStyle),
          const SizedBox(height: 8),
          TextField(
            controller: bioController,
            maxLines: 5,
            maxLength: 300,
            style: const TextStyle(fontFamily: 'Cairo'),
            decoration: _fieldDecoration("اكتب نبذة لا تتجاوز 300 حرف..."),
          ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // حفظ البيانات في خريطة التسجيل المشتركة
              widget.registrationData?['display_name'] = nameController.text.trim();
              widget.registrationData?['provider_type'] = accountType == 'فرد' ? 'individual' : 'company';
              widget.registrationData?['bio'] = bioController.text.trim();
              widget.onNext();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "التالي",
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
