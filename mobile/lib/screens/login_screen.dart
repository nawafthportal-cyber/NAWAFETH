import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../constants/colors.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../services/content_service.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/platform_top_bar.dart';
import 'signup_screen.dart';
import 'twofa_screen.dart';

class LoginScreen extends StatefulWidget {
  final Widget? redirectTo;

  const LoginScreen({super.key, this.redirectTo});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  Timer? _sendCooldownTimer;
  bool _isLoading = false;
  bool _isGuestLoading = false;
  bool _isFaceIdLoading = false;
  String? _errorMessage;
  AuthEntryContent _content = AuthEntryContent.loginDefault();
  bool _faceIdAvailable = false;
  int _sendCooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _redirectIfCompletionPending();
    _loadScreenContent();
    _checkFaceIdAvailability();
  }

  @override
  void dispose() {
    _sendCooldownTimer?.cancel();
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

  Future<void> _redirectIfCompletionPending() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) return;
    final needsCompletion = await AuthService.needsCompletion();
    if (!mounted) return;
    if (needsCompletion) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SignUpScreen(redirectTo: widget.redirectTo),
        ),
      );
      return;
    }
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  /// ✅ التحقق من صحة رقم الجوال
  bool get _isPhoneValid {
    final digits = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    return RegExp(r'^05\d{8}$').hasMatch(digits);
  }

  /// ✅ إرسال OTP عبر الـ API
  Future<void> _onSendOtp() async {
    if (_sendCooldownSeconds > 0) {
      setState(() => _errorMessage = 'يمكنك إعادة المحاولة بعد ${_formatWaitShort(_sendCooldownSeconds)}');
      return;
    }

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
            initialCooldownSeconds: result.cooldownSeconds ?? 60,
          ),
        ),
      );
    } else {
      if ((result.retryAfterSeconds ?? 0) > 0) {
        _startSendCooldown(result.retryAfterSeconds!);
      }
      setState(() => _errorMessage = result.error ?? 'فشل إرسال الرمز');
    }
  }

  void _startSendCooldown(int seconds) {
    _sendCooldownTimer?.cancel();
    if (seconds <= 0) {
      if (!mounted) return;
      setState(() => _sendCooldownSeconds = 0);
      return;
    }

    if (!mounted) return;
    setState(() => _sendCooldownSeconds = seconds);

    _sendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_sendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _sendCooldownSeconds = 0);
        return;
      }
      setState(() => _sendCooldownSeconds -= 1);
    });
  }

  String _formatWaitShort(int seconds) {
    if (seconds < 60) return '$seconds ث';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return remainingSeconds > 0 ? '$minutes د $remainingSeconds ث' : '$minutes د';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes > 0 ? '$hours س $remainingMinutes د' : '$hours س';
  }

  Future<void> _continueAsGuest() async {
    if (_isGuestLoading || _isLoading) return;

    setState(() => _isGuestLoading = true);
    await AuthService.logout();
    if (!mounted) return;
    setState(() => _isGuestLoading = false);

    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  Future<void> _checkFaceIdAvailability() async {
    try {
      final biometricData =
          await AuthService.getBiometricCredentials(clearInvalid: true);
      if (biometricData == null) return;

      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();

      if (!mounted) return;
      setState(() {
        _faceIdAvailable = canCheck && isSupported;
        if (_phoneController.text.trim().isEmpty) {
          _phoneController.text = biometricData.phone;
        }
      });
    } catch (_) {}
  }

  Future<void> _loginWithFaceId() async {
    if (_isFaceIdLoading || _isLoading) return;

    setState(() {
      _isFaceIdLoading = true;
      _errorMessage = null;
    });

    try {
      final localAuth = LocalAuthentication();
      final authenticated = await localAuth.authenticate(
        localizedReason: 'التحقق من هويتك لتسجيل الدخول',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!mounted) return;

      if (!authenticated) {
        setState(() => _isFaceIdLoading = false);
        return;
      }

      // البصمة ناجحة — تسجيل الدخول مباشرة عبر device_token
      final biometricData =
          await AuthService.getBiometricCredentials(clearInvalid: true);

      if (biometricData == null) {
        setState(() {
          _isFaceIdLoading = false;
          _errorMessage = 'لم يتم العثور على بيانات المصادقة. أعد تفعيل معرف الوجه من الإعدادات.';
        });
        return;
      }

      final result = await AuthApiService.biometricLogin(
        biometricData.phone,
        biometricData.deviceToken,
      );
      if (!mounted) return;

      setState(() => _isFaceIdLoading = false);

      if (result.success) {
        if (result.needsCompletion) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SignUpScreen(redirectTo: widget.redirectTo),
            ),
          );
        } else {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      } else {
        setState(() => _errorMessage = result.error ?? 'فشل تسجيل الدخول');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFaceIdLoading = false;
        _errorMessage = 'فشل التحقق البيومتري';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomDrawer(),
      appBar: PlatformTopBar(
        pageLabel: _content.title,
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
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
                    onPressed: (_isLoading || _sendCooldownSeconds > 0) ? null : _onSendOtp,
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
                            _sendCooldownSeconds > 0
                                ? 'أعد المحاولة بعد ${_formatWaitShort(_sendCooldownSeconds)}'
                                : _content.submitLabel,
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

                // ─── زر الدخول بمعرف الوجه ───
                if (_faceIdAvailable) ...[
                  Row(
                    children: [
                      Expanded(child: Container(height: 1, color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text("أو", style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(child: Container(height: 1, color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_isLoading || _isGuestLoading || _isFaceIdLoading) ? null : _loginWithFaceId,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isFaceIdLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.person_outline, color: Colors.white, size: 15),
                            ),
                      label: const Text('الدخول بمعرف الوجه',
                          style: TextStyle(fontSize: 15, fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
