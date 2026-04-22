import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../constants/app_theme.dart';
import '../services/app_logger.dart';
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
    } catch (error, stackTrace) {
      AppLogger.warn(
        'LoginScreen failed to load last login phone',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadScreenContent() async {
    try {
      final result = await ContentService.fetchPublicContent();
      if (!mounted || !result.isSuccess || result.dataAsMap == null) return;
      final blocks =
          (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _content = AuthEntryContent.loginFromBlocks(blocks);
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'LoginScreen failed to load screen content',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
      return 'رقم الجوال غير صحيح';
    }
    return '';
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
      setState(() => _errorMessage =
          'يمكنك إعادة المحاولة بعد ${_formatWaitShort(_sendCooldownSeconds)}');
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
      return remainingSeconds > 0
          ? '$minutes د $remainingSeconds ث'
          : '$minutes د';
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
    } catch (error, stackTrace) {
      AppLogger.warn(
        'LoginScreen biometric availability check failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
          _errorMessage =
              'لم يتم العثور على بيانات المصادقة. أعد تفعيل معرف الوجه من الإعدادات.';
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
    } catch (error, stackTrace) {
      AppLogger.warn(
        'LoginScreen biometric login failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isFaceIdLoading = false;
        _errorMessage = 'فشل التحقق البيومتري';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      drawer: const CustomDrawer(),
      backgroundColor: const Color(0xFFF7F3FC),
      appBar: PlatformTopBar(
        pageLabel: _content.title,
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final horizontalPadding = compact ? 12.0 : 16.0;
          return Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFF7F3FC),
                      Color(0xFFFBF8FF),
                      Color(0xFFF6F9FF),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                top: -86,
                right: -54,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.deepPurple.withValues(alpha: 0.11),
                  ),
                ),
              ),
              Positioned(
                bottom: -120,
                left: -66,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentOrange.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    compact ? 10 : 16,
                    horizontalPadding,
                    18 + viewInsets,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: _buildEntrance(
                      0,
                      _buildFormCard(compact: compact),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormCard({required bool compact}) {
    final headlineSize = compact ? 23.0 : 26.0;
    final sectionRadius = compact ? 24.0 : 28.0;
    final fieldRadius = compact ? 16.0 : 18.0;
    final hasHint = _phoneSupportText.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 20,
        compact ? 16 : 20,
        compact ? 16 : 20,
        compact ? 18 : 20,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(sectionRadius),
        border: Border.all(color: const Color(0xFFE5DAF4)),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFDF9FF),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1C1437).withValues(alpha: 0.09),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: AppColors.deepPurple.withValues(alpha: 0.08),
            blurRadius: 36,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF2EAFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.deepPurple.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 13,
                  color: AppColors.deepPurple.withValues(alpha: 0.88),
                ),
                const SizedBox(width: 5),
                Text(
                  'بوابة نوافذ',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepPurple.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Text(
            _content.title,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: headlineSize,
              height: 1.3,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1F1738),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'برقم الجوال',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6F6987),
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          const Text(
            'رقم الجوال',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF362F4F),
            ),
          ),
          const SizedBox(height: 7),
          _buildPhoneField(fieldRadius: fieldRadius, compact: compact),
          if (hasHint) ...[
            const SizedBox(height: 7),
            _buildHintLine(
              _phoneSupportText,
              tone: _phoneSupportTone,
              showSpinner: _isLoading,
            ),
          ],
          SizedBox(height: compact ? 14 : 16),
          SizedBox(
            width: double.infinity,
            height: compact ? 50 : 54,
            child: ElevatedButton(
              onPressed:
                  (_isLoading || _sendCooldownSeconds > 0) ? null : _onSendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepPurple,
                disabledBackgroundColor:
                    AppColors.deepPurple.withValues(alpha: 0.42),
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
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
            SizedBox(height: compact ? 13 : 15),
            _buildDivider(),
            const SizedBox(height: 12),
            _buildBiometricPanel(radius: fieldRadius),
          ],
          SizedBox(height: compact ? 13 : 15),
          _buildDivider(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: compact ? 48 : 50,
            child: OutlinedButton(
              onPressed:
                  (_isLoading || _isGuestLoading) ? null : _continueAsGuest,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepPurple,
                backgroundColor: const Color(0xFFF9F5FD),
                side: BorderSide(
                  color: AppColors.deepPurple.withValues(alpha: 0.26),
                  width: 1.05,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                ),
              ),
              child: Text(
                _isGuestLoading ? 'جارٍ التنفيذ...' : _content.guestLabel,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField({
    required double fieldRadius,
    required bool compact,
  }) {
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
      }) =>
          null,
      onChanged: (_) => setState(() => _errorMessage = null),
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        color: Color(0xFF201830),
      ),
      decoration: InputDecoration(
        hintText: '05XXXXXXXX',
        hintTextDirection: TextDirection.ltr,
        filled: true,
        fillColor: const Color(0xFFFDFBFF),
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9A93AF),
        ),
        prefixIcon: Icon(
          Icons.phone_android_rounded,
          size: compact ? 18 : 19,
          color: AppColors.deepPurple.withValues(alpha: 0.78),
        ),
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
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 15 : 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: Color(0xFFE2D8F2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: Color(0xFFE2D8F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: AppColors.deepPurple, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildBiometricPanel({required double radius}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: (_isLoading || _isGuestLoading || _isFaceIdLoading)
            ? null
            : _loginWithFaceId,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.deepPurple,
          backgroundColor: const Color(0xFFF7F2FF),
          side: BorderSide(
            color: AppColors.deepPurple.withValues(alpha: 0.3),
            width: 1.1,
          ),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        icon: _isFaceIdLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.face_retouching_natural_rounded, size: 18),
        label: const Text(
          'الدخول بمعرف الوجه',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
          ),
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
