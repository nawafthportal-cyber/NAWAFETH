import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';
import '../services/auth_api_service.dart';
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
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// ✅ التحقق من صحة رقم الجوال
  bool get _isPhoneValid {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return false;
    // يقبل أرقام سعودية: 05XXXXXXXX أو 5XXXXXXXX أو +9665XXXXXXXX
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 9 && digits.length <= 14;
  }

  /// ✅ إرسال OTP عبر الـ API
  Future<void> _onSendOtp() async {
    if (!_isPhoneValid) {
      setState(() => _errorMessage = 'أدخل رقم جوال صحيح');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final phone = _phoneController.text.trim();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "تسجيل الدخول",
          style: TextStyle(
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
                const Text(
                  "أدخل رقم الجوال لتسجيل الدخول",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "سيتم إرسال رمز تحقق إلى جوالك",
                  style: TextStyle(
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
                        : const Text(
                            "إرسال رمز التحقق",
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
