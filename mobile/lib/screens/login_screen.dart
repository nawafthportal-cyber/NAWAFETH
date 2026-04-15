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

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  late final AnimationController _entranceController;
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
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _redirectIfCompletionPending();
    _loadScreenContent();
    _loadLastLoginPhone();
    _checkFaceIdAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _sendCooldownTimer?.cancel();
    _entranceController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadLastLoginPhone() async {
    try {
      final lastPhone = await AuthService.getLastLoginPhone();
      if (!mounted || lastPhone == null || lastPhone.trim().isEmpty) return;
      if (_phoneController.text.trim().isNotEmpty) return;
      setState(() {
        _phoneController.text = lastPhone;
      });
    } catch (_) {}
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

  /// تطبيع رقم الجوال إلى صيغة 05XXXXXXXX
  String _normalizePhone05(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('009665') && digits.length == 12) {
      return '0${digits.substring(4)}';
    }
    if (digits.startsWith('9665') && digits.length == 12) {
      return '0${digits.substring(3)}';
    }
    if (digits.startsWith('5') && digits.length == 9) {
      return '0$digits';
    }
    return digits;
  }

  /// ✅ التحقق من صحة رقم الجوال
  bool get _isPhoneValid {
    final normalized = _normalizePhone05(_phoneController.text);
    return RegExp(r'^05\d{8}$').hasMatch(normalized);
  }

  String get _normalizedPhone => _normalizePhone05(_phoneController.text);

  String get _phoneSupportText {
    if ((_errorMessage ?? '').trim().isNotEmpty) {
      return _errorMessage!.trim();
    }
    if (_sendCooldownSeconds > 0) {
      return 'يمكنك إعادة المحاولة بعد ${_formatWaitShort(_sendCooldownSeconds)}';
    }
    final value = _phoneController.text.trim();
    if (value.isNotEmpty && !_isPhoneValid) {
      return 'الصيغة الصحيحة: 05XXXXXXXX';
    }
    if (value.isNotEmpty && _isPhoneValid) {
      return 'الرقم جاهز لإرسال رمز التحقق.';
    }
    return _content.phoneHint;
  }

  _LoginHintTone get _phoneSupportTone {
    if ((_errorMessage ?? '').trim().isNotEmpty) {
      return _LoginHintTone.bad;
    }
    final value = _phoneController.text.trim();
    if (value.isNotEmpty && !_isPhoneValid) {
      return _LoginHintTone.bad;
    }
    if (value.isNotEmpty && _isPhoneValid) {
      return _LoginHintTone.ok;
    }
    return _LoginHintTone.neutral;
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

    final phone = _normalizePhone05(_phoneController.text);
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
      backgroundColor: const Color(0xFFF7F3FC),
      appBar: PlatformTopBar(
        pageLabel: _content.title,
        showBackButton: Navigator.of(context).canPop(),
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  _buildEntrance(0, _buildFormCard()),
                ],
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
            top: -32,
            left: -24,
            child: Container(
              width: 128,
              height: 128,
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
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF49BFD2).withValues(alpha: 0.18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadge('دخول آمن وسريع', dark: true),
              const SizedBox(height: 14),
              Text(
                _content.title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
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
              _buildHeroPoint('إرسال رمز تحقق سريع ومباشر إلى رقم الجوال.'),
              const SizedBox(height: 8),
              _buildHeroPoint('دخول بيومتري عند توفره على الجهاز والحساب.'),
              const SizedBox(height: 8),
              _buildHeroPoint('إمكانية المتابعة كضيف دون تعطيل تجربة التصفح.'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _LoginShowcaseTag(label: 'OTP من 4 أرقام'),
                  if (_faceIdAvailable) _LoginShowcaseTag(label: 'معرف الوجه'),
                  _LoginShowcaseTag(label: 'وضع ضيف'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
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
            'ابدأ برقم الجوال',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F1738),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أدخل الرقم بصيغة محلية صحيحة، وسنأخذك مباشرة إلى خطوة التحقق دون تعقيد.',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.9,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6F6987),
            ),
          ),
          const SizedBox(height: 14),
          _buildPhoneField(),
          const SizedBox(height: 8),
          _buildHintLine(
            _phoneSupportText,
            tone: _phoneSupportTone,
            showSpinner: _isLoading,
          ),
          if (_sendCooldownSeconds > 0) ...[
            const SizedBox(height: 10),
            _buildCooldownPanel(),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_isLoading || _sendCooldownSeconds > 0) ? null : _onSendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepPurple,
                disabledBackgroundColor:
                    AppColors.deepPurple.withValues(alpha: 0.42),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
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
                        fontSize: 14,
                        fontFamily: 'Cairo',
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
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepPurple,
                backgroundColor: const Color(0xFFF7F2FF),
                side: BorderSide(
                  color: AppColors.deepPurple.withValues(alpha: 0.35),
                  width: 1.1,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      maxLength: 10,
      buildCounter: (
        BuildContext context, {
        required int currentLength,
        required bool isFocused,
        required int? maxLength,
      }) => null,
      onChanged: (_) => setState(() => _errorMessage = null),
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF201830),
      ),
      decoration: InputDecoration(
        labelText: 'رقم الجوال',
        hintText: '05XXXXXXXX',
        hintTextDirection: TextDirection.ltr,
        filled: true,
        fillColor: const Color(0xFFFCFBFE),
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF655D7B),
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9A93AF),
        ),
        prefixIcon: const Icon(Icons.phone_android_rounded, size: 19),
        prefixIconColor: AppColors.deepPurple,
        suffixIcon: _normalizedPhone.isEmpty
            ? null
            : Icon(
                _isPhoneValid
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: _isPhoneValid
                    ? const Color(0xFF1B8A5A)
                    : const Color(0xFFBB4257),
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE6DFF2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE6DFF2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.deepPurple, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildCooldownPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DAF6)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.deepPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.timer_outlined,
              size: 18,
              color: AppColors.deepPurple,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ننتظر انتهاء مهلة الإرسال قبل محاولة جديدة. الوقت المتبقي: ${_formatWaitShort(_sendCooldownSeconds)}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                height: 1.8,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5E5579),
              ),
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
            'إذا كان الجهاز والحساب يدعمان المصادقة البيومترية، يمكنك الدخول بخطوة أسرع دون انتظار رمز جديد.',
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
              onPressed: (_isLoading || _isGuestLoading || _isFaceIdLoading)
                  ? null
                  : _loginWithFaceId,
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
              label: const Text(
                'الدخول بمعرف الوجه',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Cairo',
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
    required _LoginHintTone tone,
    bool showSpinner = false,
  }) {
    Color color;
    switch (tone) {
      case _LoginHintTone.ok:
        color = const Color(0xFF1B8A5A);
        break;
      case _LoginHintTone.bad:
        color = const Color(0xFFBB4257);
        break;
      case _LoginHintTone.neutral:
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

enum _LoginHintTone { neutral, ok, bad }

class _LoginShowcaseTag extends StatelessWidget {
  final String label;

  const _LoginShowcaseTag({required this.label});

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
