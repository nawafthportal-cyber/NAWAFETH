import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../widgets/platform_top_bar.dart';

class FaceIDIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FaceIDIcon({super.key, this.size = 26, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.person_outline, color: color, size: size * 0.7),
    );
  }
}

class LoginSettingsScreen extends StatefulWidget {
  const LoginSettingsScreen({super.key});

  @override
  State<LoginSettingsScreen> createState() => _LoginSettingsScreenState();
}

class _LoginSettingsScreenState extends State<LoginSettingsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primaryColor = Color(0xFF0E7490);
  static const Color _primaryDark = Color(0xFF0F5D78);

  late final AnimationController _entranceController;
  final LocalAuthentication _localAuth = LocalAuthentication();

  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  bool _biometricAvailable = false;
  bool _faceIdEnabled = false;
  bool _faceIdLoading = false;

  bool _requiresUnlock = false;
  bool _isUnlocked = true;
  String _enteredPin = '';
  String? _storedPin;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _initializeAccessFlow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeAccessFlow() async {
    await _checkBiometrics();
    final pin = await AuthService.getSecurityPin();
    if (!mounted) return;

    if (pin == null) {
      _requiresUnlock = false;
      _isUnlocked = true;
      _loadProfile();
      return;
    }

    setState(() {
      _storedPin = pin;
      _requiresUnlock = true;
      _isUnlocked = false;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ProfileService.fetchMyProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      _applyProfile(result.data!);
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _error = result.error ?? 'تعذر تحميل بيانات الحساب حالياً';
      _loading = false;
    });
  }

  void _applyProfile(UserProfile profile) {
    _profile = profile;
    _phoneCtrl.text = profile.phone ?? '';
    _emailCtrl.text = profile.email ?? '';
    _firstNameCtrl.text = profile.firstName ?? '';
    _lastNameCtrl.text = profile.lastName ?? '';
  }

  Future<void> _updateProfileFields(
    Map<String, dynamic> data,
    String successMessage,
  ) async {
    if (data.isEmpty) {
      _snack('لا يوجد تغييرات');
      return;
    }

    setState(() => _saving = true);
    final result = await ProfileService.updateMyProfile(data);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.isSuccess && result.data != null) {
      setState(() => _applyProfile(result.data!));
      _snack(successMessage, success: true);
      return;
    }

    _snack(result.error ?? 'فشل حفظ التغييرات');
  }

  Future<void> _changeUsername(String username) async {
    final normalized = username.trim();
    if (normalized.isEmpty) {
      _snack('اسم العضوية مطلوب');
      return;
    }

    setState(() => _saving = true);
    final response = await ApiClient.post(
      '/api/accounts/change-username/',
      body: {'username': normalized},
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (!response.isSuccess) {
      _snack(response.error ?? 'تعذر تغيير اسم العضوية');
      return;
    }

    await _loadProfile();
    if (!mounted) return;
    _snack('تم تغيير اسم العضوية بنجاح', success: true);
  }

  Future<void> _changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      _snack('يرجى تعبئة جميع حقول كلمة المرور');
      return;
    }

    setState(() => _saving = true);
    final response = await ApiClient.post(
      '/api/accounts/change-password/',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirm': confirmPassword,
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (!response.isSuccess) {
      _snack(response.error ?? 'تعذر تغيير كلمة المرور');
      return;
    }

    _snack('تم تغيير كلمة المرور بنجاح', success: true);
  }

  void _snack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: success ? const Color(0xFF1B8A5A) : Colors.red.shade700,
      ),
    );
  }

  PlatformTopBar _settingsTopBar() {
    return PlatformTopBar(
      pageLabel: 'إعدادات الدخول',
      showBackButton: Navigator.of(context).canPop(),
      showNotificationAction: false,
      showChatAction: false,
    );
  }

  Future<void> _showUsernameDialog() async {
    final controller = TextEditingController(text: _profile?.username ?? '');
    await _showActionDialog(
      title: 'تغيير اسم العضوية',
      description:
          'أدخل اسم العضوية الجديد. يفضل استخدام صيغة واضحة وسهلة التذكر.',
      hint: 'يسمح عادة بالأحرف الإنجليزية والأرقام وبعض الرموز البسيطة.',
      fields: [
        _DialogFieldConfig(
          label: 'اسم العضوية الجديد',
          controller: controller,
          textDirection: TextDirection.ltr,
          maxLength: 50,
        ),
      ],
      onSubmit: () => _changeUsername(controller.text),
    );
  }

  Future<void> _showNameDialog() async {
    final firstCtrl = TextEditingController(text: _firstNameCtrl.text);
    final lastCtrl = TextEditingController(text: _lastNameCtrl.text);
    await _showActionDialog(
      title: 'تعديل الاسم الشخصي',
      description: 'يمكنك تحديث الاسم الأول واسم العائلة كما سيظهران في الحساب.',
      hint: 'تأكد من كتابة الاسم بشكل صحيح قبل الحفظ.',
      fields: [
        _DialogFieldConfig(label: 'الاسم الأول', controller: firstCtrl),
        _DialogFieldConfig(label: 'اسم العائلة', controller: lastCtrl),
      ],
      onSubmit: () => _updateProfileFields(
        {
          'first_name': firstCtrl.text.trim(),
          'last_name': lastCtrl.text.trim(),
        },
        'تم تحديث الاسم بنجاح',
      ),
    );
  }

  Future<void> _showEmailDialog() async {
    final controller = TextEditingController(text: _emailCtrl.text);
    await _showActionDialog(
      title: 'تغيير البريد الإلكتروني',
      description: 'أدخل البريد الإلكتروني الجديد المرتبط بحسابك.',
      hint: 'تأكد من صحة البريد حتى تصلك الإشعارات بشكل سليم.',
      fields: [
        _DialogFieldConfig(
          label: 'البريد الإلكتروني',
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          maxLength: 255,
        ),
      ],
      onSubmit: () => _updateProfileFields(
        {'email': controller.text.trim()},
        'تم تحديث البريد الإلكتروني بنجاح',
      ),
    );
  }

  Future<void> _showPhoneDialog() async {
    final controller = TextEditingController(text: _phoneCtrl.text);
    await _showActionDialog(
      title: 'تغيير رقم الجوال',
      description: 'أدخل رقم الجوال بالصيغة المحلية الصحيحة 05XXXXXXXX.',
      hint: 'سيتم استخدام هذا الرقم في مسارات التحقق والدخول البيومتري.',
      fields: [
        _DialogFieldConfig(
          label: 'رقم الجوال',
          controller: controller,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          maxLength: 10,
        ),
      ],
      onSubmit: () async {
        final normalized = AuthService.normalizePhoneLocal05(controller.text.trim());
        if (normalized == null) {
          _snack('صيغة رقم الجوال يجب أن تكون 05XXXXXXXX');
          return;
        }
        await _updateProfileFields(
          {'phone': normalized},
          'تم تحديث رقم الجوال بنجاح',
        );
      },
    );
  }

  Future<void> _showPasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    await _showActionDialog(
      title: 'تغيير كلمة المرور',
      description: 'أدخل كلمة المرور الحالية ثم الجديدة مع التأكيد.',
      hint: 'يفضل استخدام كلمة مرور قوية لا تقل عن 8 أحرف.',
      fields: [
        _DialogFieldConfig(
          label: 'كلمة المرور الحالية',
          controller: currentCtrl,
          obscureText: true,
          textDirection: TextDirection.ltr,
        ),
        _DialogFieldConfig(
          label: 'كلمة المرور الجديدة',
          controller: newCtrl,
          obscureText: true,
          textDirection: TextDirection.ltr,
        ),
        _DialogFieldConfig(
          label: 'تأكيد كلمة المرور الجديدة',
          controller: confirmCtrl,
          obscureText: true,
          textDirection: TextDirection.ltr,
        ),
      ],
      onSubmit: () => _changePassword(
        currentPassword: currentCtrl.text.trim(),
        newPassword: newCtrl.text.trim(),
        confirmPassword: confirmCtrl.text.trim(),
      ),
    );
  }

  Future<void> _showPinDialog() async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    await _showActionDialog(
      title: _storedPin == null ? 'إضافة رمز دخول أمان' : 'تعديل رمز دخول الأمان',
      description:
          'يحمي هذا الرمز إعدادات الدخول على الجهاز الحالي ويستخدم قبل فتح الشاشة.',
      hint: 'يمكنك إدخال رمز من 4 إلى 6 أرقام.',
      fields: [
        _DialogFieldConfig(
          label: 'رمز الأمان',
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          textDirection: TextDirection.ltr,
          maxLength: 6,
        ),
        _DialogFieldConfig(
          label: 'تأكيد الرمز',
          controller: confirmCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          textDirection: TextDirection.ltr,
          maxLength: 6,
        ),
      ],
      onSubmit: () async {
        final pin = pinCtrl.text.trim();
        final confirm = confirmCtrl.text.trim();
        if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
          _snack('رمز الأمان يجب أن يكون من 4 إلى 6 أرقام');
          return;
        }
        if (pin != confirm) {
          _snack('تأكيد الرمز غير مطابق');
          return;
        }
        await AuthService.saveSecurityPin(pin);
        if (!mounted) return;
        setState(() {
          _storedPin = pin;
          _requiresUnlock = true;
        });
        _snack('تم حفظ رمز الأمان', success: true);
      },
      extraActions: _storedPin == null
          ? null
          : [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      title: const Text(
                        'إزالة رمز الأمان',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      content: const Text(
                        'هل تريد إزالة رمز الأمان من هذا الجهاز؟',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'إزالة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await AuthService.clearSecurityPin();
                  if (!mounted) return;
                  setState(() {
                    _storedPin = null;
                    _requiresUnlock = false;
                  });
                  _snack('تمت إزالة رمز الأمان', success: true);
                },
                child: const Text(
                  'إزالة الرمز',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
    );
  }

  Future<void> _showActionDialog({
    required String title,
    required String description,
    required String hint,
    required List<_DialogFieldConfig> fields,
    required Future<void> Function() onSubmit,
    List<Widget>? extraActions,
  }) async {
    var localSaving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          content: StatefulBuilder(
            builder: (context, setLocalState) {
              Future<void> submit() async {
                if (localSaving) return;
                setLocalState(() => localSaving = true);
                await onSubmit();
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          height: 1.8,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B657A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F9FB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x330E7490)),
                        ),
                        child: Text(
                          hint,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F5D78),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...fields.map(_buildDialogField),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (extraActions != null) ...extraActions,
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text(
                              'إلغاء',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: localSaving ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: localSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'حفظ التغييرات',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDialogField(_DialogFieldConfig config) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: config.controller,
        keyboardType: config.keyboardType,
        obscureText: config.obscureText,
        textDirection: config.textDirection,
        maxLength: config.maxLength,
        decoration: InputDecoration(
          labelText: config.label,
          counterText: '',
          labelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF5F6D80),
          ),
          filled: true,
          fillColor: const Color(0xFFFBFCFD),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFDCE6ED)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _primaryColor, width: 1.4),
          ),
        ),
      ),
    );
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final biometricData =
          await AuthService.getBiometricCredentials(clearInvalid: true);

      if (!mounted) return;
      setState(() {
        _biometricAvailable = canCheck && isSupported;
        _faceIdEnabled = biometricData != null && _biometricAvailable;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _biometricAvailable = false);
    }
  }

  Future<void> _enrollFaceId() async {
    setState(() => _faceIdLoading = true);

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'قم بالتحقق من هويتك لتفعيل الدخول بمعرف الوجه',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!mounted) return;

      if (authenticated) {
        final enrollResult = await AuthApiService.biometricEnroll();
        if (!mounted) return;

        if (!enrollResult.success || enrollResult.deviceToken == null) {
          setState(() => _faceIdLoading = false);
          _snack(enrollResult.error ?? 'فشل تسجيل المصادقة البيومترية');
          return;
        }

        final phone = AuthService.normalizePhoneLocal05(_phoneCtrl.text.trim()) ??
            await AuthService.getLastLoginPhone();
        if (phone == null) {
          setState(() => _faceIdLoading = false);
          _snack(
            'تعذر تحديد رقم الجوال المرتبط بالحساب. أعد تسجيل الدخول عبر OTP ثم حاول مرة أخرى.',
          );
          return;
        }
        await AuthService.saveBiometricCredentials(
          phone: phone,
          deviceToken: enrollResult.deviceToken!,
        );

        setState(() {
          _faceIdEnabled = true;
          _faceIdLoading = false;
        });
        _snack('تم تفعيل الدخول بمعرف الوجه بنجاح', success: true);
      } else {
        setState(() => _faceIdLoading = false);
        _snack('تم إلغاء عملية التحقق');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _faceIdLoading = false);
      _snack('فشل التحقق البيومتري');
    }
  }

  Future<void> _disableFaceId() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'إلغاء معرف الوجه',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
            color: _primaryDark,
          ),
        ),
        content: const Text(
          'هل تريد إلغاء تفعيل الدخول بمعرف الوجه على هذا الجهاز؟',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'إلغاء التفعيل',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await AuthApiService.biometricRevoke();
    await AuthService.clearBiometricCredentials();

    if (!mounted) return;
    setState(() => _faceIdEnabled = false);
    _snack('تم إلغاء تفعيل معرف الوجه', success: true);
  }

  void _appendUnlockDigit(String digit) {
    if (_storedPin == null) return;
    if (_enteredPin.length >= _storedPin!.length) return;
    setState(() {
      _enteredPin += digit;
      _unlockError = null;
    });
    if (_enteredPin.length == _storedPin!.length) {
      _validateUnlockPin();
    }
  }

  void _removeUnlockDigit() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _unlockError = null;
    });
  }

  void _validateUnlockPin() {
    if (_storedPin == null) {
      _completeUnlock();
      return;
    }
    if (_enteredPin == _storedPin) {
      _completeUnlock();
      return;
    }
    setState(() {
      _enteredPin = '';
      _unlockError = 'رمز الأمان غير صحيح';
    });
  }

  Future<void> _unlockWithBiometric() async {
    if (!_biometricAvailable || !_faceIdEnabled) return;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'التحقق من هويتك للدخول إلى إعدادات الدخول',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!mounted) return;
      if (authenticated) {
        _completeUnlock();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _unlockError = 'تعذر التحقق بالبصمة أو الوجه');
    }
  }

  void _completeUnlock() {
    setState(() {
      _isUnlocked = true;
      _enteredPin = '';
      _unlockError = null;
    });
    _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_requiresUnlock && !_isUnlocked) {
      return _buildUnlockScreen(isDark);
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
        appBar: _settingsTopBar(),
        body: _buildLoadingState(isDark),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
        appBar: _settingsTopBar(),
        body: _buildErrorState(isDark),
      );
    }

    final profile = _profile!;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
      appBar: _settingsTopBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  colors: [Color(0xFF0E1726), Color(0xFF122235), Color(0xFF17293D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xFFEEF5FB), Color(0xFFF4F7FB), Color(0xFFF7F8FC)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          children: [
            _buildEntrance(0, _buildHeroCard(profile, isDark)),
            const SizedBox(height: 14),
            _buildEntrance(1, _buildIdentityCard(profile, isDark)),
            const SizedBox(height: 14),
            _buildEntrance(2, _buildAccountActionsCard(profile, isDark)),
            const SizedBox(height: 14),
            _buildEntrance(3, _buildSecurityCard(isDark)),
            const SizedBox(height: 14),
            _buildEntrance(4, _buildBiometricCard(isDark)),
            if (_saving) ...[
              const SizedBox(height: 14),
              _buildSavingBanner(isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C223D).withValues(alpha: isDark ? 0.12 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _primaryColor),
            SizedBox(height: 14),
            Text(
              'جاري تحميل إعدادات الدخول...',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0x220E5E85),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _error ?? 'حدث خطأ غير متوقع',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(UserProfile profile, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0E7490), Color(0xFF1D4ED8)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.16),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -46,
            left: -18,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -58,
            right: -24,
            child: Container(
              width: 164,
              height: 164,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadge('الهوية والأمان'),
              const SizedBox(height: 12),
              const Text(
                'إعدادات الدخول',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'البيانات الأساسية والأمان البيومتري ورمز الجهاز في واجهة واحدة أوضح وأهدأ، مع تعديل مباشر لكل عنصر تحتاجه.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroMetaChip(label: 'اسم العضوية', value: _valueOrDash(profile.username)),
                  _HeroMetaChip(label: 'البريد', value: _valueOrDash(profile.email)),
                  _HeroMetaChip(label: 'الجوال', value: _valueOrDash(profile.phone)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(UserProfile profile, bool isDark) {
    return _surfaceCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الهوية الحالية',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ملخص سريع للبيانات الأساسية المرتبطة بتسجيل الدخول لهذا الحساب.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF142B3C), Color(0xFF102432)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFF6FBFD)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0x220E5E85),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF0E7490)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: const Icon(Icons.verified_user_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.usernameDisplay,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF4F657D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountActionsCard(UserProfile profile, bool isDark) {
    return _surfaceCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'بيانات تسجيل الدخول',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'يمكنك تعديل كل عنصر بشكل منفصل مع حفظ فوري ورسائل واضحة للنجاح أو الخطأ.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
            ),
          ),
          const SizedBox(height: 12),
          _SettingActionTile(
            title: 'اسم العضوية',
            value: _valueOrDash(profile.username),
            buttonLabel: 'تعديل',
            onTap: _showUsernameDialog,
          ),
          const SizedBox(height: 10),
          _SettingActionTile(
            title: 'الاسم الشخصي',
            value: [profile.firstName ?? '', profile.lastName ?? '']
                .where((part) => part.trim().isNotEmpty)
                .join(' ')
                .trim()
                .isEmpty
                ? 'غير مضاف'
                : [profile.firstName ?? '', profile.lastName ?? '']
                    .where((part) => part.trim().isNotEmpty)
                    .join(' '),
            buttonLabel: 'تعديل',
            onTap: _showNameDialog,
          ),
          const SizedBox(height: 10),
          _SettingActionTile(
            title: 'البريد الإلكتروني',
            value: _valueOrDash(profile.email),
            buttonLabel: 'تعديل',
            onTap: _showEmailDialog,
          ),
          const SizedBox(height: 10),
          _SettingActionTile(
            title: 'رقم الجوال',
            value: _valueOrDash(profile.phone),
            buttonLabel: 'تعديل',
            onTap: _showPhoneDialog,
          ),
          const SizedBox(height: 10),
          _SettingActionTile(
            title: 'كلمة المرور',
            value: 'محمية ولا يمكن عرضها. يمكنك تغييرها في أي وقت.',
            buttonLabel: 'تغيير',
            strongButton: true,
            onTap: _showPasswordDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(bool isDark) {
    final pinActive = _storedPin != null;
    return _surfaceCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الأمان الإضافي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'فعّل حماية محلية إضافية لهذا الجهاز باستخدام رمز أمان قصير.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: pinActive
                  ? const Color(0xFFF0FAF5)
                  : const Color(0xFFFFF6E9),
              border: Border.all(
                color: pinActive
                    ? const Color(0xFFB8E0C9)
                    : const Color(0xFFF4D19C),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  pinActive ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: pinActive ? const Color(0xFF1B8A5A) : const Color(0xFFC07A17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'رمز دخول الأمان',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: pinActive ? const Color(0xFF1B8A5A) : const Color(0xFF8F5A07),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pinActive
                            ? 'مفعل حالياً لهذا الجهاز. سيُطلب قبل فتح إعدادات الدخول.'
                            : 'غير مفعل حالياً. يمكنك إضافته لطبقة حماية محلية أسرع.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          height: 1.8,
                          fontWeight: FontWeight.w700,
                          color: pinActive ? const Color(0xFF2A6E53) : const Color(0xFF8C6729),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showPinDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: const BorderSide(color: _primaryColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: const Icon(Icons.key_rounded, size: 18),
              label: Text(
                pinActive ? 'إضافة أو تعديل الرمز' : 'إضافة رمز دخول أمان',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricCard(bool isDark) {
    return _surfaceCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الدخول بمعرف الوجه',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'فعّل المصادقة البيومترية على الجهاز لتسريع الدخول مع الحفاظ على التحقق المرتبط بالحساب.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF52637A),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: _faceIdEnabled
                    ? [const Color(0xFFF0FAF5), const Color(0xFFF5FFFA)]
                    : [const Color(0xFFF4F8FF), const Color(0xFFF9FBFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(
                color: _faceIdEnabled
                    ? const Color(0xFFB8E0C9)
                    : const Color(0xFFCCE0F8),
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
                      colors: [Color(0xFF0F766E), Color(0xFF0E7490)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: const Center(
                    child: FaceIDIcon(size: 20, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !_biometricAvailable
                            ? 'الميزة غير مدعومة'
                            : _faceIdEnabled
                                ? 'معرف الوجه مفعل'
                                : 'المعرف متاح للتفعيل',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: !_biometricAvailable
                              ? const Color(0xFF8F5A07)
                              : _faceIdEnabled
                                  ? const Color(0xFF1B8A5A)
                                  : const Color(0xFF0F5D78),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !_biometricAvailable
                            ? 'الجهاز الحالي لا يوفّر دعماً جاهزاً للمصادقة البيومترية.'
                            : _faceIdEnabled
                                ? 'الدخول البيومتري مرتبط حالياً بهذا الجهاز ويمكنك إلغاؤه متى أردت.'
                                : 'يمكن تفعيل المصادقة البيومترية بعد التحقق من هوية المستخدم على الجهاز.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          height: 1.8,
                          fontWeight: FontWeight.w700,
                          color: !_biometricAvailable
                              ? const Color(0xFF8C6729)
                              : _faceIdEnabled
                                  ? const Color(0xFF2A6E53)
                                  : const Color(0xFF41627B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: !_biometricAvailable || _faceIdLoading
                  ? null
                  : (_faceIdEnabled ? _disableFaceId : _enrollFaceId),
              style: ElevatedButton.styleFrom(
                backgroundColor: _faceIdEnabled ? Colors.red.shade600 : _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: _faceIdLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : (_faceIdEnabled
                      ? const Icon(Icons.close_rounded, size: 18)
                      : const FaceIDIcon(size: 18, color: Colors.white)),
              label: Text(
                !_biometricAvailable
                    ? 'غير مدعوم على هذا الجهاز'
                    : _faceIdEnabled
                        ? 'إلغاء التفعيل'
                        : 'الدخول بمعرف الوجه',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x220E5E85),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _primaryColor,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'جاري تنفيذ التحديث المطلوب...',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF52637A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockScreen(bool isDark) {
    final dotsCount = (_storedPin ?? '').isNotEmpty ? _storedPin!.length : 6;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
      appBar: _settingsTopBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  colors: [Color(0xFF0E1726), Color(0xFF122235), Color(0xFF17293D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xFFEEF5FB), Color(0xFFF4F7FB), Color(0xFFF7F8FC)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF0E7490), Color(0xFF1D4ED8)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0C223D).withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBadge('حماية محلية'),
                      const SizedBox(height: 12),
                      const Text(
                        'أدخل رمز حسابك',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'هذه الشاشة محمية برمز الجهاز. يمكنك أيضاً استخدام المصادقة البيومترية إذا كانت مفعلة.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          height: 1.9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0x220E5E85),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0C223D).withValues(alpha: isDark ? 0.10 : 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(dotsCount, (index) {
                          final filled = index < _enteredPin.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? _primaryColor
                                  : const Color(0xFFD3DFE6),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _unlockError != null
                            ? Text(
                                _unlockError!,
                                key: ValueKey(_unlockError),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.red,
                                ),
                              )
                            : const SizedBox(height: 18),
                      ),
                      const SizedBox(height: 8),
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.25,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          ...List.generate(
                            9,
                            (i) => _buildPinKey('${i + 1}', onTap: () => _appendUnlockDigit('${i + 1}')),
                          ),
                          const SizedBox.shrink(),
                          _buildPinKey('0', onTap: () => _appendUnlockDigit('0')),
                          _buildPinKey('⌫', onTap: _removeUnlockDigit),
                        ],
                      ),
                      if (_biometricAvailable && _faceIdEnabled) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _unlockWithBiometric,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEAF7F9),
                              foregroundColor: _primaryDark,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.fingerprint_rounded, size: 18),
                            label: const Text(
                              'الدخول بالبصمة أو الوجه',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinKey(String label, {required VoidCallback onTap}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: const Color(0xFFF7FBFD),
        foregroundColor: _primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: const BorderSide(color: Color(0xFFD9E6EC)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: _primaryDark,
        ),
      ),
    );
  }

  Widget _surfaceCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x220E5E85),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.94),
        ),
      ),
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

  String _valueOrDash(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? 'غير مضاف' : text;
  }
}

class _DialogFieldConfig {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextDirection? textDirection;
  final int? maxLength;

  const _DialogFieldConfig({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.textDirection,
    this.maxLength,
  });
}

class _SettingActionTile extends StatelessWidget {
  final String title;
  final String value;
  final String buttonLabel;
  final bool strongButton;
  final VoidCallback onTap;

  const _SettingActionTile({
    required this.title,
    required this.value,
    required this.buttonLabel,
    required this.onTap,
    this.strongButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFF9FBFD),
        border: Border.all(color: const Color(0xFFDCE6ED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    height: 1.8,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF52637A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  strongButton ? const Color(0xFF0F5D78) : const Color(0xFFEAF7F9),
              foregroundColor: strongButton ? Colors.white : const Color(0xFF0F5D78),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              buttonLabel,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
