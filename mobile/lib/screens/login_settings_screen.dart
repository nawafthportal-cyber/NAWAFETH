import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_client.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/content_service.dart';
import '../models/user_profile.dart';
import '../widgets/content_block_media.dart';
import '../widgets/platform_top_bar.dart';

/// أيقونة Face ID
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

class _LoginSettingsScreenState extends State<LoginSettingsScreen> {
  static const Color _mainColor = Colors.deepPurple;

  // بيانات من API
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  // متحكمات
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  // الأمان (محلي)
  final _securityCodeCtrl = TextEditingController();
  final _confirmSecurityCodeCtrl = TextEditingController();

  // البيومتري (بصمة / معرف الوجه)
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _biometricAvailable = false;
  bool _faceIdEnabled = false;
  bool _faceIdLoading = false;

  // قفل الدخول المحلي للشاشة
  bool _requiresUnlock = false;
  bool _isUnlocked = true;
  String _enteredPin = '';
  String? _storedPin;
  String? _unlockError;

  // محتوى المساعدة من API (settings_help / settings_info)
  String? _helpTitle;
  String? _helpBody;
  String? _helpMediaUrl;
  String? _helpMediaType;
  String? _infoTitle;
  String? _infoBody;
  String? _infoMediaUrl;
  String? _infoMediaType;

  @override
  void initState() {
    super.initState();
    _initializeAccessFlow();
  }

  Future<void> _initializeAccessFlow() async {
    await _checkBiometrics();
    final pin = await AuthService.getSecurityPin();
    if (!mounted) return;

    if (pin == null) {
      _requiresUnlock = false;
      _isUnlocked = true;
      _loadProfile();
      _loadHelpContent();
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

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _securityCodeCtrl.dispose();
    _confirmSecurityCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ProfileService.fetchMyProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      final p = result.data!;
      setState(() {
        _profile = p;
        _phoneCtrl.text = p.phone ?? '';
        _emailCtrl.text = p.email ?? '';
        _firstNameCtrl.text = p.firstName ?? '';
        _lastNameCtrl.text = p.lastName ?? '';
        _loading = false;
      });
    } else {
      setState(() {
        _error = result.error ?? 'خطأ غير متوقع';
        _loading = false;
      });
    }
  }

  /// تحميل محتوى المساعدة/المعلومات من API
  Future<void> _loadHelpContent() async {
    try {
      final result = await ContentService.fetchPublicContent();
      if (!mounted) return;
      if (result.isSuccess && result.dataAsMap != null) {
        final blocks =
            (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};

        final help = blocks['settings_help'];
        final info = blocks['settings_info'];

        setState(() {
          if (help is Map<String, dynamic>) {
            _helpTitle = (help['title_ar'] as String?)?.trim();
            _helpBody = (help['body_ar'] as String?)?.trim();
            _helpMediaUrl = ApiClient.buildMediaUrl(help['media_url']?.toString());
            _helpMediaType = (help['media_type'] as String?)?.trim();
          }
          if (info is Map<String, dynamic>) {
            _infoTitle = (info['title_ar'] as String?)?.trim();
            _infoBody = (info['body_ar'] as String?)?.trim();
            _infoMediaUrl = ApiClient.buildMediaUrl(info['media_url']?.toString());
            _infoMediaType = (info['media_type'] as String?)?.trim();
          }
        });
      }
    } catch (_) {
      // fallback — لا شيء
    }
  }

  Future<void> _saveChanges() async {
    if (_profile == null) return;

    final data = <String, dynamic>{};
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();

    if (phone != (_profile!.phone ?? '')) data['phone'] = phone;
    if (email != (_profile!.email ?? '')) data['email'] = email;
    if (firstName != (_profile!.firstName ?? '')) data['first_name'] = firstName;
    if (lastName != (_profile!.lastName ?? '')) data['last_name'] = lastName;

    if (data.isEmpty) {
      _snack('لا يوجد تغييرات');
      return;
    }

    setState(() => _saving = true);
    final result = await ProfileService.updateMyProfile(data);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.isSuccess && result.data != null) {
      setState(() {
        _profile = result.data!;
        _phoneCtrl.text = result.data!.phone ?? '';
        _emailCtrl.text = result.data!.email ?? '';
        _firstNameCtrl.text = result.data!.firstName ?? '';
        _lastNameCtrl.text = result.data!.lastName ?? '';
      });
      _snack('تم حفظ التغييرات بنجاح');
    } else {
      _snack(result.error ?? 'فشل الحفظ');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor:
          msg.contains('بنجاح') ? Colors.green : Colors.red.shade700,
    ));
  }

  PlatformTopBar _settingsTopBar() {
    return PlatformTopBar(
      pageLabel: 'إعدادات الدخول',
      showBackButton: Navigator.of(context).canPop(),
      showNotificationAction: false,
      showChatAction: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_requiresUnlock && !_isUnlocked) {
      return _buildUnlockScreen();
    }

    if (_loading) {
      return Scaffold(
        appBar: _settingsTopBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: _settingsTopBar(),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: _loadProfile,
              child: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo'))),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _settingsTopBar(),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── الهيدر ───
          Column(children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: _mainColor,
              child: const Icon(Icons.person, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 12),
            Text(
              _profile?.username ?? '',
              style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold),
            ),
            Text(
              _profile?.email ?? '',
              style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(height: 20),
          ]),

          // ─── معلومات الحساب ───
          _buildSection('معلومات الحساب', [
            _buildField(
              icon: Icons.person_outline,
              label: 'اسم العضوية',
              controller:
                  TextEditingController(text: _profile?.username ?? ''),
              enabled: false, // username immutable
            ),
            _buildField(
              icon: Icons.badge_outlined,
              label: 'الاسم الأول',
              controller: _firstNameCtrl,
            ),
            _buildField(
              icon: Icons.badge_outlined,
              label: 'اسم العائلة',
              controller: _lastNameCtrl,
            ),
            _buildField(
              icon: Icons.phone_android,
              label: 'رقم الجوال',
              controller: _phoneCtrl,
            ),
          ]),
          const SizedBox(height: 20),

          // ─── الأمان ───
          _buildSection('الأمان', [
            _buildField(
              icon: Icons.email_outlined,
              label: 'البريد الإلكتروني',
              controller: _emailCtrl,
            ),
            const SizedBox(height: 12),
            _buildPurpleButton(
              icon: Icons.key,
              label: 'إضافة رمز دخول أمان',
              onPressed: _showSecurityDialog,
            ),
          ]),
          const SizedBox(height: 20),

          // ─── طرق الدخول الإضافية ───
          _buildSection('طرق الدخول الإضافية', [
            if (!_biometricAvailable)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withAlpha(60)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'جهازك لا يدعم التحقق البيومتري (معرف الوجه / البصمة)',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ]),
              )
            else if (_faceIdEnabled) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withAlpha(60)),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'معرف الوجه مفعّل على هذا الجهاز',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _faceIdLoading ? null : _disableFaceId,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('إلغاء التفعيل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ] else
              _buildPurpleButton(
                iconWidget: _faceIdLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const FaceIDIcon(size: 22, color: Colors.white),
                label: 'الدخول بمعرف الوجه',
                onPressed: _faceIdLoading ? () {} : _enrollFaceId,
              ),
          ]),
          const SizedBox(height: 20),

          // ─── محتوى المساعدة من لوحة التحكم ───
          if (_helpTitle != null && _helpTitle!.isNotEmpty ||
              _helpBody != null && _helpBody!.isNotEmpty ||
              _helpMediaUrl != null && _helpMediaUrl!.isNotEmpty)
            _buildContentCard(
              icon: Icons.help_outline,
              title: _helpTitle ?? 'مساعدة',
              body: _helpBody ?? '',
              color: Colors.orange,
              mediaUrl: _helpMediaUrl,
              mediaType: _helpMediaType,
            ),

          if (_infoTitle != null && _infoTitle!.isNotEmpty ||
              _infoBody != null && _infoBody!.isNotEmpty ||
              _infoMediaUrl != null && _infoMediaUrl!.isNotEmpty)
            _buildContentCard(
              icon: Icons.info_outline,
              title: _infoTitle ?? 'معلومات',
              body: _infoBody ?? '',
              color: Colors.blue,
              mediaUrl: _infoMediaUrl,
              mediaType: _infoMediaType,
            ),

          const SizedBox(height: 30),

          // ─── زر الحفظ ───
          ElevatedButton(
            onPressed: _saving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('حفظ التغييرات',
                    style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─── نوافذ محلية ───

  void _showSecurityDialog() {
    showDialog(
      context: context,
      builder: (_) => Center(
        child: Card(
          color: Colors.white,
          elevation: 12,
          shadowColor: Colors.black45,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IntrinsicHeight(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                        icon: const Icon(Icons.close, color: _mainColor),
                        onPressed: () => Navigator.pop(context))),
                const Text('إضافة رمز دخول أمان',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _mainColor)),
                const SizedBox(height: 10),
                const Text(
                    '⚠️ احتفظ بالرمز في مكان آمن ولا تشاركه مع أحد.',
                    style: TextStyle(fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextField(
                    controller: _securityCodeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration:
                        const InputDecoration(labelText: 'رمز الأمان (4-6 أرقام)')),
                const SizedBox(height: 10),
                TextField(
                    controller: _confirmSecurityCodeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration:
                        const InputDecoration(labelText: 'تأكيد رمز الأمان')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    final pin = _securityCodeCtrl.text.trim();
                    final confirm = _confirmSecurityCodeCtrl.text.trim();
                    final isValid = RegExp(r'^\d{4,6}$').hasMatch(pin);

                    if (!isValid) {
                      _snack('رمز الأمان يجب أن يكون من 4 إلى 6 أرقام');
                      return;
                    }
                    if (pin != confirm) {
                      _snack('تأكيد الرمز غير مطابق');
                      return;
                    }

                    await AuthService.saveSecurityPin(pin);
                    if (!mounted) return;

                    _securityCodeCtrl.clear();
                    _confirmSecurityCodeCtrl.clear();
                    Navigator.pop(context);
                    _snack('تم حفظ رمز الأمان');
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _mainColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('حفظ'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ─── البيومتري (معرف الوجه / البصمة) ───

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
        // تسجيل device_token من السيرفر
        final enrollResult = await AuthApiService.biometricEnroll();
        if (!mounted) return;

        if (!enrollResult.success || enrollResult.deviceToken == null) {
          setState(() => _faceIdLoading = false);
          _snack(enrollResult.error ?? 'فشل تسجيل المصادقة البيومترية');
          return;
        }

        final phone =
            AuthService.normalizePhoneLocal05(_phoneCtrl.text.trim()) ??
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
        _snack('تم تفعيل الدخول بمعرف الوجه بنجاح');
      } else {
        setState(() => _faceIdLoading = false);
        _snack('تم إلغاء عملية التحقق');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _faceIdLoading = false);
      _snack('فشل التحقق البيومتري');
    }
  }

  Future<void> _disableFaceId() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('إلغاء معرف الوجه',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: _mainColor)),
        content: const Text('هل تريد إلغاء تفعيل الدخول بمعرف الوجه؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لا', style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم', style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // إلغاء من السيرفر
    await AuthApiService.biometricRevoke();

    await AuthService.clearBiometricCredentials();

    if (!mounted) return;
    setState(() => _faceIdEnabled = false);
    _snack('تم إلغاء تفعيل معرف الوجه');
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
      setState(() => _unlockError = 'تعذر التحقق بالبصمة/الوجه');
    }
  }

  void _completeUnlock() {
    setState(() {
      _isUnlocked = true;
      _enteredPin = '';
      _unlockError = null;
    });
    _loadProfile();
    _loadHelpContent();
  }

  Widget _buildUnlockScreen() {
    final dotsCount = (_storedPin ?? '').isNotEmpty ? _storedPin!.length : 6;
    return Scaffold(
      appBar: _settingsTopBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          child: Column(
            children: [
              const Text(
                'أدخل رمز حسابك',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _mainColor,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(dotsCount, (index) {
                  final filled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? _mainColor : const Color(0xFFD9C4DD),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              if (_unlockError != null)
                Text(
                  _unlockError!,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                const SizedBox(height: 22),
              const SizedBox(height: 14),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.6,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ...List.generate(9, (i) => _buildPinKey('${i + 1}', onTap: () => _appendUnlockDigit('${i + 1}'))),
                    const SizedBox.shrink(),
                    _buildPinKey('0', onTap: () => _appendUnlockDigit('0')),
                    _buildPinKey('⌫', onTap: _removeUnlockDigit),
                  ],
                ),
              ),
              if (_biometricAvailable && _faceIdEnabled)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _unlockWithBiometric,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE5CEE8),
                      foregroundColor: _mainColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.fingerprint, color: _mainColor),
                    label: const Text(
                      'الدخول عن طريق البصمة / الوجه',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
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
        backgroundColor: Colors.transparent,
        foregroundColor: _mainColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: _mainColor,
        ),
      ),
    );
  }

  // ─── مكونات UI ───

  /// كرت محتوى (مساعدة / معلومات) من لوحة التحكم
  Widget _buildContentCard({
    required IconData icon,
    required String title,
    required String body,
    required Color color,
    String? mediaUrl,
    String? mediaType,
  }) {
    final normalizedMediaUrl = (mediaUrl ?? '').trim();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: color.withAlpha(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withAlpha(40),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color.withAlpha(220),
                  ),
                ),
              ),
            ]),
            if (normalizedMediaUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ContentBlockMedia(
                mediaUrl: normalizedMediaUrl,
                mediaType: (mediaType ?? '').trim(),
                aspectRatio: 16 / 9,
                borderRadius: 18,
              ),
            ],
            if (body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                body,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 0,
      color: _mainColor.withAlpha(13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _mainColor)),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }

  Widget _buildField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    bool enabled = true,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _mainColor),
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _mainColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _mainColor, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  Widget _buildPurpleButton({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _mainColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: iconWidget ?? Icon(icon, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
    );
  }
}
