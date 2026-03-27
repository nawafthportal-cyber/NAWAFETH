import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../constants/colors.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../services/content_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/platform_top_bar.dart';
import 'signup_screen.dart';

class TwoFAScreen extends StatefulWidget {
  final String phone;
  final Widget? redirectTo;
  final Widget? nextPage;

  const TwoFAScreen({
    super.key,
    required this.phone,
    this.redirectTo,
    this.nextPage,
  });

  @override
  State<TwoFAScreen> createState() => _TwoFAScreenState();
}

class _TwoFAScreenState extends State<TwoFAScreen> {
  final List<TextEditingController> _digitControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes = List.generate(4, (_) => FocusNode());

  Timer? _countdownTimer;

  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;

  int _resendCountdown = 60;
  bool _canResend = false;
  TwofaContent _content = TwofaContent.defaults();

  String get _code => _digitControllers.map((c) => c.text).join();
  bool get _isCodeComplete => RegExp(r'^\d{4}$').hasMatch(_code);

  bool _faceIdAvailable = false;
  bool _isFaceIdLoading = false;

  @override
  void initState() {
    super.initState();
    _loadScreenContent();
    _startCountdown();
    _checkFaceIdAvailability();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _setError(String? value) {
    if (!mounted) return;
    setState(() => _errorMessage = value);
  }

  void _clearError() {
    if (_errorMessage == null) return;
    _setError(null);
  }

  void _setCode(String code) {
    final digits = code.replaceAll(RegExp(r'[^\d]'), '');
    for (var i = 0; i < 4; i++) {
      _digitControllers[i].text = i < digits.length ? digits[i] : '';
    }
  }

  void _onDigitChanged(int index, String value) {
    _clearError();

    final normalized = value.replaceAll(RegExp(r'[^\d]'), '');
    if (normalized.length > 1) {
      _setCode(normalized);
      if (_isCodeComplete) {
        FocusScope.of(context).unfocus();
      }
      setState(() {});
      return;
    }

    if (normalized.isEmpty) {
      if (index > 0) {
        _digitFocusNodes[index - 1].requestFocus();
      }
      setState(() {});
      return;
    }

    _digitControllers[index].text = normalized;
    _digitControllers[index].selection = TextSelection.fromPosition(
      TextPosition(offset: _digitControllers[index].text.length),
    );

    if (index < 3) {
      _digitFocusNodes[index + 1].requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
    setState(() {});
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() {
          _resendCountdown = 0;
          _canResend = true;
        });
        return;
      }
      setState(() => _resendCountdown -= 1);
    });
  }

  Future<void> _loadScreenContent() async {
    try {
      final result = await ContentService.fetchPublicContent();
      if (!mounted || !result.isSuccess || result.dataAsMap == null) return;
      final blocks = (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _content = TwofaContent.fromBlocks(blocks);
      });
    } catch (_) {}
  }

  Future<void> _onVerifyOtp() async {
    if (!_isCodeComplete) {
      _setError('أدخل رمز التحقق المكوّن من 4 أرقام');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await AuthApiService.verifyOtp(widget.phone, _code);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      if (result.needsCompletion) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SignUpScreen(
              redirectTo: widget.redirectTo ?? widget.nextPage,
            ),
          ),
        );
      } else {
        _navigateAfterLogin();
      }
      return;
    }

    _setError(result.error ?? 'الرمز غير صحيح');
  }

  Future<void> _onResendOtp() async {
    if (!_canResend || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final result = await AuthApiService.sendOtp(widget.phone);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.success) {
      _startCountdown();
      final text = result.devCode != null
          ? '${_content.successResendLabel} - رمز التطوير: ${result.devCode}'
          : _content.successResendLabel;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    _setError(result.error ?? 'فشل إعادة الإرسال');
  }

  Future<void> _checkFaceIdAvailability() async {
    try {
      final biometricData =
          await AuthService.getBiometricCredentials(clearInvalid: true);
      if (biometricData == null) return;

      // التحقق أن الرقم المحفوظ هو نفس الرقم المستخدم حالياً
      final currentPhone = AuthService.normalizePhoneLocal05(widget.phone);
      if (currentPhone == null || biometricData.phone != currentPhone) return;

      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();

      if (!mounted) return;
      setState(() => _faceIdAvailable = canCheck && isSupported);
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

      // البصمة ناجحة → تسجيل الدخول بالـ device_token
      final biometricData =
          await AuthService.getBiometricCredentials(clearInvalid: true);

      if (biometricData == null) {
        setState(() {
          _isFaceIdLoading = false;
          _errorMessage = 'بيانات المصادقة غير متوفرة. أعد تفعيل معرف الوجه.';
        });
        return;
      }

      final currentPhone = AuthService.normalizePhoneLocal05(widget.phone);
      if (currentPhone == null || biometricData.phone != currentPhone) {
        setState(() {
          _isFaceIdLoading = false;
          _errorMessage =
              'معرف الوجه مفعّل لرقم جوال مختلف. استخدم OTP أو أعد تفعيل معرف الوجه.';
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
              builder: (_) => SignUpScreen(
                redirectTo: widget.redirectTo ?? widget.nextPage,
              ),
            ),
          );
        } else {
          _navigateAfterLogin();
        }
        return;
      }

      _setError(result.error ?? 'فشل تسجيل الدخول بالمعرف');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFaceIdLoading = false;
        _errorMessage = 'فشل التحقق البيومتري';
      });
    }
  }

  void _navigateAfterLogin() {
    PushNotificationService.tryRegisterCurrentToken();
    final target = widget.redirectTo ?? widget.nextPage;
    if (target != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => target),
        (route) => false,
      );
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  Widget _buildOtpBox(int index) {
    final hasValue = _digitControllers[index].text.isNotEmpty;

    return SizedBox(
      width: 62,
      child: TextField(
        controller: _digitControllers[index],
        focusNode: _digitFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: index == 3 ? TextInputAction.done : TextInputAction.next,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        onSubmitted: (_) {
          if (index == 3 && _isCodeComplete && !_isLoading) {
            _onVerifyOtp();
          }
        },
        onChanged: (value) => _onDigitChanged(index, value),
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.deepPurple,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          filled: true,
          fillColor: hasValue ? const Color(0xFFF4F0FF) : const Color(0xFFF9FAFB),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasValue ? AppColors.deepPurple : const Color(0xFFD9DCE3),
              width: hasValue ? 1.3 : 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.deepPurple, width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: PlatformTopBar(
        pageLabel: _content.title,
        showBackButton: true,
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFE7FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.deepPurple,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _content.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _content.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _content.phoneNotice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.phone,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, _buildOtpBox),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _onVerifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepPurple,
                        disabledBackgroundColor:
                            AppColors.deepPurple.withValues(alpha: 0.45),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _content.submitLabel,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    if (_faceIdAvailable) ...[
                      Row(
                        children: [
                          const Expanded(child: Divider(endIndent: 8)),
                          Text(
                            'أو',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const Expanded(child: Divider(indent: 8)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _isFaceIdLoading ? null : _loginWithFaceId,
                        icon: _isFaceIdLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.deepPurple,
                                ),
                              )
                            : const Icon(Icons.face, size: 22),
                        label: Text(
                          _isFaceIdLoading ? 'جاري التحقق...' : 'الدخول بمعرف الوجه',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.deepPurple,
                          side: const BorderSide(color: AppColors.deepPurple, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _content.resendPrompt,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        TextButton(
                          onPressed: _canResend && !_isResending ? _onResendOtp : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(20, 24),
                          ),
                          child: _isResending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _content.resendLabel,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    if (!_canResend)
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F1FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        child: Text(
                            '${_content.resendLabel} بعد $_resendCountdown ثانية',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                              color: AppColors.deepPurple,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TwofaContent {
  final String title;
  final String description;
  final String submitLabel;
  final String resendLabel;
  final String successResendLabel;
  final String phoneNotice;
  final String resendPrompt;

  const TwofaContent({
    required this.title,
    required this.description,
    required this.submitLabel,
    required this.resendLabel,
    required this.successResendLabel,
    required this.phoneNotice,
    required this.resendPrompt,
  });

  factory TwofaContent.defaults() {
    return const TwofaContent(
      title: 'التحقق من الرمز',
      description: 'أدخل رمز التحقق المكوّن من 4 أرقام الذي تم إرساله إلى رقم الجوال.',
      submitLabel: 'تأكيد الرمز',
      resendLabel: 'إعادة الإرسال',
      successResendLabel: 'تم إرسال رمز جديد',
      phoneNotice: 'تم إرسال الرمز إلى',
      resendPrompt: 'لم يصلك الرمز؟',
    );
  }

  factory TwofaContent.fromBlocks(Map<String, dynamic> blocks) {
    String resolve(String key, String fallback) {
      final block = blocks[key];
      if (block is! Map<String, dynamic>) return fallback;
      final title = (block['title_ar'] as String?)?.trim() ?? '';
      return title.isNotEmpty ? title : fallback;
    }

    return TwofaContent(
      title: resolve('twofa_title', 'التحقق من الرمز'),
      description: resolve(
        'twofa_description',
        'أدخل رمز التحقق المكوّن من 4 أرقام الذي تم إرساله إلى رقم الجوال.',
      ),
      submitLabel: resolve('twofa_submit_label', 'تأكيد الرمز'),
      resendLabel: resolve('twofa_resend_label', 'إعادة الإرسال'),
      successResendLabel: resolve('twofa_success_resend_label', 'تم إرسال رمز جديد'),
      phoneNotice: resolve('twofa_phone_notice', 'تم إرسال الرمز إلى'),
      resendPrompt: resolve('twofa_resend_prompt', 'لم يصلك الرمز؟'),
    );
  }
}
