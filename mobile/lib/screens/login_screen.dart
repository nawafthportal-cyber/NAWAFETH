import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../constants/app_theme.dart';
import '../services/app_logger.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../services/content_service.dart';
import '../utils/responsive.dart';
import 'signup_screen.dart';
import 'twofa_screen.dart';

String? validateLoginPhoneInput(String raw) {
  if (raw.trim().isEmpty) {
    return 'أدخل رقم الجوال للمتابعة';
  }
  if (AuthService.normalizePhoneLocal05(raw) == null) {
    return 'الصيغة الصحيحة: 05XXXXXXXX';
  }
  return null;
}

class LoginScreen extends StatefulWidget {
  final Widget? redirectTo;

  const LoginScreen({super.key, this.redirectTo});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
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
    _phoneFocusNode.dispose();
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
  bool get _isPhoneValid =>
      validateLoginPhoneInput(_phoneController.text) == null;

  String get _normalizedPhone => _normalizePhone05(_phoneController.text);

  String get _phoneSupportText {
    if ((_errorMessage ?? '').trim().isNotEmpty) {
      return _errorMessage!.trim();
    }
    if (_sendCooldownSeconds > 0) {
      return 'يمكنك إعادة المحاولة بعد ${_formatWaitShort(_sendCooldownSeconds)}';
    }
    final value = _phoneController.text.trim();
    final validationMessage = validateLoginPhoneInput(value);
    if (value.isNotEmpty && validationMessage != null) {
      return validationMessage;
    }
    if (value.isNotEmpty && validationMessage == null) {
      return 'سيتم إرسال رمز تحقق إلى هذا الرقم';
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
    if (_isLoading) return;
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
      FocusScope.of(context).unfocus();
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.devCode != null && kDebugMode
                ? 'تم إرسال الرمز. رمز التطوير: ${result.devCode}'
                : 'تم إرسال رمز التحقق إلى $phone',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ),
      );

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
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = ResponsiveLayout.isCompactWidth(context);
          final horizontalPadding = ResponsiveLayout.horizontalPadding(context);
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFF8F5FC),
                        Color(0xFFFFFFFF),
                        Color(0xFFF5F1FB),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      compact ? 16 : 28,
                      horizontalPadding,
                      compact ? 18 + viewInsets : 28 + viewInsets,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: ResponsiveLayout.contentMaxWidth(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (Navigator.of(context).canPop())
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: IconButton.filledTonal(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                            ),
                          _buildBrandHeader(compact: compact),
                          SizedBox(height: compact ? 16 : 22),
                          _buildEntrance(0, _buildFormCard(compact: compact)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormCard({required bool compact}) {
    final theme = Theme.of(context);
    final headlineSize = compact ? 26.0 : 30.0;
    final sectionRadius = compact ? 24.0 : 30.0;
    final fieldRadius = compact ? 18.0 : 22.0;
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
          Text(
            _content.title,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: headlineSize,
              height: 1.2,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1F1738),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _content.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6F6987),
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          _buildInfoStrip(
            icon: Icons.sms_outlined,
            text: _content.phoneHint,
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
          Semantics(
            textField: true,
            label: 'حقل رقم الجوال',
            child: _buildPhoneField(fieldRadius: fieldRadius, compact: compact),
          ),
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
                minimumSize: Size.fromHeight(compact ? 52 : 56),
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
                        fontSize: 15,
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
          _buildSecondaryActions(fieldRadius: fieldRadius, compact: compact),
        ],
      ),
    );
  }

  Widget _buildBrandHeader({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: compact ? 64 : 76,
          height: compact ? 64 : 76,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.elevated,
          ),
          child: const Icon(
            Icons.window_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Text(
            'تسجيل دخول سريع وآمن',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField({
    required double fieldRadius,
    required bool compact,
  }) {
    return TextField(
      controller: _phoneController,
      focusNode: _phoneFocusNode,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      textDirection: TextDirection.ltr,
      autofillHints: const [AutofillHints.telephoneNumberNational],
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
      onSubmitted: (_) => _onSendOtp(),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      scrollPadding: const EdgeInsets.only(bottom: 120),
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF201830),
      ),
      decoration: InputDecoration(
        labelText: 'رقم الجوال',
        hintText: '05XXXXXXXX',
        hintTextDirection: TextDirection.ltr,
        filled: true,
        fillColor: const Color(0xFFFDFBFF),
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
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

  Widget _buildInfoStrip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3D6F5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.deepPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w700,
                color: Color(0xFF645B7D),
              ),
            ),
          ),
        ],
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
            fontSize: 14,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryActions({
    required double fieldRadius,
    required bool compact,
  }) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: compact ? 50 : 52,
          child: OutlinedButton(
            onPressed:
                (_isLoading || _isGuestLoading) ? null : _continueAsGuest,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepPurple,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: AppColors.deepPurple.withValues(alpha: 0.36),
                width: 1.3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(fieldRadius),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isGuestLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.person_outline_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  _isGuestLoading ? 'جارٍ التنفيذ...' : _content.guestLabel,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppColors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            const Text(
              'ليس لديك حساب؟',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF786F8B),
              ),
            ),
            TextButton(
              onPressed: (_isLoading || _isGuestLoading || _isFaceIdLoading)
                  ? null
                  : _openCreateAccount,
              child: const Text('إنشاء حساب'),
            ),
          ],
        ),
      ],
    );
  }

  void _openCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignUpScreen(redirectTo: widget.redirectTo),
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
      title: 'مرحبًا بعودتك',
      description: 'سجّل دخولك للمتابعة إلى حسابك عبر رقم الجوال ورمز التحقق.',
      phoneHint: 'أدخل رقم الجوال المسجل وسنرسل لك رمز تحقق للمتابعة.',
      submitLabel: 'تسجيل الدخول',
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
      title: resolve('login_title', 'مرحبًا بعودتك'),
      description: resolve(
        'login_description',
        'سجّل دخولك للمتابعة إلى حسابك عبر رقم الجوال ورمز التحقق.',
      ),
      phoneHint: resolve(
        'login_phone_hint',
        'أدخل رقم الجوال المسجل وسنرسل لك رمز تحقق للمتابعة.',
      ),
      submitLabel: resolve('login_submit_label', 'تسجيل الدخول'),
      guestLabel: resolve('login_guest_label', 'المتابعة كضيف'),
    );
  }
}
