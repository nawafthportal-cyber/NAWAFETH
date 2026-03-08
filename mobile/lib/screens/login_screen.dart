import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../services/content_service.dart';
import '../widgets/custom_drawer.dart';
import 'twofa_screen.dart';

class LoginScreen extends StatefulWidget {
  final Widget? redirectTo;

  const LoginScreen({super.key, this.redirectTo});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isGuestLoading = false;
  String? _errorMessage;
  AuthEntryContent _content = AuthEntryContent.loginDefault();

  @override
  void initState() {
    super.initState();
    _loadScreenContent();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadScreenContent() async {
    try {
      final result = await ContentService.fetchPublicContent();
      if (!mounted || !result.isSuccess || result.dataAsMap == null) return;
      final blocks = (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _content = AuthEntryContent.loginFromBlocks(blocks);
      });
    } catch (_) {}
  }

  /// ✅ التحقق من صحة رقم الجوال
  bool get _isPhoneValid {
    final digits = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    return RegExp(r'^05\d{8}$').hasMatch(digits);
  }

  /// ✅ إرسال OTP عبر الـ API
  Future<void> _onSendOtp() async {
    if (!_isPhoneValid) {
      setState(() => _errorMessage = 'الصيغة الصحيحة: 05XXXXXXXX');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final phone = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    final result = await AuthApiService.sendOtp(phone);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.success) {
      // ✅ في بيئة التطوير نعرض الكود
      if (result.devCode != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('رمز التطوير: ${result.devCode}',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // الانتقال لشاشة إدخال الرمز
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TwoFAScreen(
            phone: phone,
            redirectTo: widget.redirectTo,
          ),
        ),
      );
    } else {
      setState(() => _errorMessage = result.error ?? 'فشل إرسال الرمز');
    }
  }

  Future<void> _continueAsGuest() async {
    if (_isGuestLoading || _isLoading) return;

    setState(() => _isGuestLoading = true);
    await AuthService.logout();
    if (!mounted) return;
    setState(() => _isGuestLoading = false);

    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          _content.title,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((0.05 * 255).toInt()),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _content.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _content.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 20),

                // حقل رقم الجوال
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  maxLength: 10,
                  buildCounter:
                      (
                        BuildContext context, {
                        required int currentLength,
                        required bool isFocused,
                        required int? maxLength,
                      }) => null,
                  onChanged: (_) => setState(() => _errorMessage = null),
                  decoration: InputDecoration(
                    labelText: "رقم الجوال",
                    hintText: "05XXXXXXXX",
                    hintTextDirection: TextDirection.ltr,
                    helperText: _content.phoneHint,
                    helperStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    prefixIcon: const Icon(Icons.phone_android),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    errorText: _errorMessage,
                    errorStyle: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(height: 20),

                // زر الإرسال
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onSendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _content.submitLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        "أو",
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_isLoading || _isGuestLoading) ? null : _continueAsGuest,
                    icon: _isGuestLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_outline_rounded, size: 18),
                    label: Text(
                      _content.guestLabel,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.deepPurple,
                      backgroundColor: const Color(0xFFF7F2FF),
                      side: BorderSide(
                        color: AppColors.deepPurple.withAlpha(90),
                        width: 1.1,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthEntryContent {
  final String title;
  final String description;
  final String phoneHint;
  final String submitLabel;
  final String guestLabel;

  const AuthEntryContent({
    required this.title,
    required this.description,
    required this.phoneHint,
    required this.submitLabel,
    required this.guestLabel,
  });

  factory AuthEntryContent.loginDefault() {
    return const AuthEntryContent(
      title: 'تسجيل الدخول',
      description: 'أدخل رقم الجوال وسنرسل لك رمز تحقق لإكمال الدخول بأمان.',
      phoneHint: 'الصيغة المعتمدة: 05XXXXXXXX',
      submitLabel: 'إرسال رمز التحقق',
      guestLabel: 'المتابعة كضيف',
    );
  }

  factory AuthEntryContent.loginFromBlocks(Map<String, dynamic> blocks) {
    String resolve(String key, String fallback) {
      final block = blocks[key];
      if (block is! Map<String, dynamic>) return fallback;
      final title = (block['title_ar'] as String?)?.trim() ?? '';
      return title.isNotEmpty ? title : fallback;
    }

    return AuthEntryContent(
      title: resolve('login_title', 'تسجيل الدخول'),
      description: resolve(
        'login_description',
        'أدخل رقم الجوال وسنرسل لك رمز تحقق لإكمال الدخول بأمان.',
      ),
      phoneHint: resolve('login_phone_hint', 'الصيغة المعتمدة: 05XXXXXXXX'),
      submitLabel: resolve('login_submit_label', 'إرسال رمز التحقق'),
      guestLabel: resolve('login_guest_label', 'المتابعة كضيف'),
    );
  }
}
