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
  final int initialCooldownSeconds;

  const TwoFAScreen({
    super.key,
    required this.phone,
    this.redirectTo,
    this.nextPage,
    this.initialCooldownSeconds = 60,
  });

  @override
  State<TwoFAScreen> createState() => _TwoFAScreenState();
}

class _TwoFAScreenState extends State<TwoFAScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _digitControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes = List.generate(4, (_) => FocusNode());
  late final AnimationController _entranceController;

  Timer? _countdownTimer;

  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;

  int _resendCountdown = 60;
  bool _canResend = false;
  TwofaContent _content = TwofaContent.defaults();

  bool _faceIdAvailable = false;
  bool _isFaceIdLoading = false;

  String get _code => _digitControllers.map((c) => c.text).join();
  bool get _isCodeComplete => RegExp(r'^\d{4}$').hasMatch(_code);
  String get _normalizedPhone =>
      AuthService.normalizePhoneLocal05(widget.phone) ?? widget.phone;

  String get _codeSupportText {
    if ((_errorMessage ?? '').trim().isNotEmpty) {
      return _errorMessage!.trim();
    }
    if (_isCodeComplete) {
      return 'الرمز مكتمل وجاهز للتأكيد.';
    }
    final enteredDigits = _code.length;
    if (enteredDigits > 0) {
      return 'أدخل ${4 - enteredDigits} أرقام إضافية لإكمال التحقق.';
    }
    return _content.description;
  }

  _TwofaHintTone get _codeSupportTone {
    if ((_errorMessage ?? '').trim().isNotEmpty) {
      return _TwofaHintTone.bad;
    }
    if (_isCodeComplete) {
      return _TwofaHintTone.ok;
    }
    return _TwofaHintTone.neutral;
  }

  String get _resendCountdownLabel =>
      '${_content.resendLabel} بعد ${_formatWaitShort(_resendCountdown)}';

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _loadScreenContent();
    _startCountdown(widget.initialCooldownSeconds);
    _checkFaceIdAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
        _digitFocusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _entranceController.dispose();
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
    if (mounted) {
      setState(() {});
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

  void _startCountdown([int seconds = 60]) {
    _countdownTimer?.cancel();

    if (seconds <= 0) {
      setState(() {
        _resendCountdown = 0;
        _canResend = true;
      });
      return;
    }

    setState(() {
      _resendCountdown = seconds;
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
      _startCountdown(result.cooldownSeconds ?? widget.initialCooldownSeconds);
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

    if ((result.retryAfterSeconds ?? 0) > 0) {
      _startCountdown(result.retryAfterSeconds!);
    }

    _setError(result.error ?? 'فشل إعادة الإرسال');
  }

  Future<void> _pasteCodeFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final digits = (data?.text ?? '').replaceAll(RegExp(r'[^\d]'), '').trim();
    if (digits.length < 4) {
      _setError('لم يتم العثور على رمز مكوّن من 4 أرقام في الحافظة');
      return;
    }

    _clearError();
    _setCode(digits.substring(0, 4));
    FocusScope.of(context).unfocus();
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

  Future<void> _checkFaceIdAvailability() async {
    try {
      final biometricData =
          await AuthService.getBiometricCredentials(clearInvalid: true);
      if (biometricData == null) return;

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
    } catch (_) {
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
      width: 66,
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
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: AppColors.deepPurple,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
          filled: true,
          fillColor: hasValue ? const Color(0xFFF3ECFF) : const Color(0xFFFCFBFE),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: hasValue ? AppColors.deepPurple : const Color(0xFFE2DCEB),
              width: hasValue ? 1.3 : 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: AppColors.deepPurple, width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3FC),
      appBar: PlatformTopBar(
        pageLabel: _content.title,
        showBackButton: true,
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8F4FF), Color(0xFFFDFBFE), Color(0xFFF6FAFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    _buildEntrance(0, _buildVerificationCard()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShowcaseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF241249), Color(0xFF4E2F97)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B1756).withValues(alpha: 0.18),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -34,
            left: -26,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -48,
            right: -22,
            child: Container(
              width: 152,
              height: 152,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF49BFD2).withValues(alpha: 0.18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadge('تحقق آمن', dark: true),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _content.title,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _content.description,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
              const SizedBox(height: 14),
              _buildHeroPoint('أدخل الرمز المكوّن من 4 أرقام لتأكيد الجلسة بسرعة.'),
              const SizedBox(height: 8),
              _buildHeroPoint('يمكن إعادة إرسال رمز جديد حسب مهلة الباكند المعتمدة.'),
              const SizedBox(height: 8),
              _buildHeroPoint('معرف الوجه يظهر فقط عندما يكون مربوطاً لنفس رقم الجوال.'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _TwofaShowcaseTag(label: 'OTP من 4 أرقام'),
                  const _TwofaShowcaseTag(label: 'مهلة إعادة إرسال'),
                  if (_faceIdAvailable) const _TwofaShowcaseTag(label: 'معرف الوجه'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE6DAF6)),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF9F5FD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1C1437).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'أدخل الرمز المرسل',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F1738),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'نرسل رمزاً قصيراً إلى رقم الجوال المؤكد لإكمال الدخول بدون خطوات زائدة.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.9,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6F6987),
            ),
          ),
          const SizedBox(height: 14),
          _buildPhoneNoticePanel(),
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(4, _buildOtpBox),
            ),
          ),
          const SizedBox(height: 10),
          _buildHintLine(
            _codeSupportText,
            tone: _codeSupportTone,
            showSpinner: _isLoading,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isLoading ? null : _pasteCodeFromClipboard,
              icon: const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text(
                'لصق الرمز من الحافظة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _onVerifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepPurple,
                disabledBackgroundColor:
                    AppColors.deepPurple.withValues(alpha: 0.45),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          if (_faceIdAvailable) ...[
            const SizedBox(height: 16),
            _buildDivider(),
            const SizedBox(height: 14),
            _buildBiometricPanel(),
          ],
          const SizedBox(height: 16),
          _buildDivider(),
          const SizedBox(height: 14),
          _buildResendPanel(),
        ],
      ),
    );
  }

  Widget _buildPhoneNoticePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8DFF4)),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7F3FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF4D2997), Color(0xFF7A4FD1)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: const Icon(Icons.sms_outlined, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _content.phoneNotice,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF72698B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _normalizedPhone,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF201830),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6DAF6)),
        gradient: const LinearGradient(
          colors: [Color(0xFFFBFAFE), Color(0xFFF5F9FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4D2997), Color(0xFF7A4FD1)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: const Icon(Icons.face_retouching_natural_rounded,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'الدخول بمعرف الوجه',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F1738),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'إذا كان هذا الرقم مرتبطاً بالمصادقة البيومترية على الجهاز، يمكنك إكمال الدخول مباشرة دون كتابة الرمز.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: Color(0xFF645B7D),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isLoading || _isFaceIdLoading) ? null : _loginWithFaceId,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: _isFaceIdLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.fingerprint_rounded, size: 18),
              label: Text(
                _isFaceIdLoading ? 'جاري التحقق...' : 'الدخول بمعرف الوجه',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResendPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8DFF4)),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF8F4FD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _content.resendPrompt,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5F5977),
                  ),
                ),
              ),
              TextButton(
                onPressed: _canResend && !_isResending ? _onResendOtp : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.deepPurple,
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
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _canResend
                ? Container(
                    key: const ValueKey('resend-ready'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FAF5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'يمكنك طلب رمز جديد الآن.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B8A5A),
                      ),
                    ),
                  )
                : Container(
                    key: const ValueKey('resend-waiting'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F1FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _resendCountdownLabel,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepPurple,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftPanel({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8DFF4)),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7F3FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF4D2997), Color(0xFF7A4FD1)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F1738),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    height: 1.8,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5F5977),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPoint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF49BFD2), Color(0xFFD2A14C)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: const Icon(Icons.check, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.82,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String label, {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFF1EAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: dark ? const Color(0xFFFFF5D8) : const Color(0xFF4D2997),
        ),
      ),
    );
  }

  Widget _buildHintLine(
    String text, {
    required _TwofaHintTone tone,
    bool showSpinner = false,
  }) {
    Color color;
    switch (tone) {
      case _TwofaHintTone.ok:
        color = const Color(0xFF1B8A5A);
        break;
      case _TwofaHintTone.bad:
        color = const Color(0xFFBB4257);
        break;
      case _TwofaHintTone.neutral:
        color = const Color(0xFF7C748F);
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Row(
        key: ValueKey('$text-$tone-$showSpinner'),
        children: [
          if (showSpinner) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFE3DDF0))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'أو',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8A82A0),
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFFE3DDF0))),
      ],
    );
  }

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.08 * index).clamp(0.0, 0.8).toDouble();
    final end = (begin + 0.34).clamp(0.0, 1.0).toDouble();
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

enum _TwofaHintTone { neutral, ok, bad }

class _TwofaShowcaseTag extends StatelessWidget {
  final String label;

  const _TwofaShowcaseTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.92),
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
