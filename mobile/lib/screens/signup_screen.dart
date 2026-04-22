import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../constants/app_theme.dart';
import '../constants/saudi_cities.dart';
import '../services/auth_api_service.dart';
import '../services/content_service.dart';
import '../services/geo_catalog_service.dart';
import '../services/app_logger.dart';
import '../widgets/platform_top_bar.dart';
import 'terms_screen.dart';

class SignUpScreen extends StatefulWidget {
  final Widget? redirectTo;

  const SignUpScreen({super.key, this.redirectTo});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final AnimationController _entranceController;

  Timer? _usernameDebounce;

  List<SaudiRegionCatalogEntry> _regionCatalog = const [];
  String? _selectedRegion;
  String? _selectedCity;
  bool _agreeToTerms = false;
  bool _isLoading = false;
  bool _isSkipLoading = false;
  bool _isRegionCatalogLoading = true;
  bool _usedRegionFallback = false;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameHint;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _generalError;
  Map<String, String>? _fieldErrors;
  String? _regionError;
  String? _cityError;
  SignupContent _content = SignupContent.defaults();

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1280),
    );
    _loadScreenContent();
    _loadRegionCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  bool get _isPasswordValid => _passwordController.text.length >= 8;
  bool get _hasLowercase => _passwordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasUppercase => _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial =>
      _passwordController.text.contains(RegExp(r'[!@#\$&*~%^()\-_=+{};:,<.>]'));

  bool get _isAllValid =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      (_selectedRegion?.isNotEmpty ?? false) &&
      (_selectedCity?.isNotEmpty ?? false) &&
      _passwordController.text == _confirmPasswordController.text &&
      _isPasswordValid &&
      _hasLowercase &&
      _hasUppercase &&
      _hasNumber &&
      _hasSpecial &&
      (_isUsernameAvailable == true) &&
      !_isCheckingUsername &&
      !_isRegionCatalogLoading &&
      _agreeToTerms;

  SaudiRegionCatalogEntry? get _activeRegion {
    final selected = _selectedRegion?.trim();
    if (selected == null || selected.isEmpty) return null;
    for (final region in _regionCatalog) {
      if (region.nameAr == selected || region.displayName == selected) {
        return region;
      }
    }
    return null;
  }

  List<String> get _availableCities => _activeRegion?.cities ?? const [];

  String get _regionHintText {
    if (_isRegionCatalogLoading) {
      return 'جاري تحميل المناطق الإدارية المتاحة...';
    }
    if (_selectedRegion == null || _selectedRegion!.trim().isEmpty) {
      return 'اختر المنطقة أولًا لتصفية المدن التابعة لها.';
    }
    return 'تم اختيار المنطقة. اختر الآن المدينة التابعة لها.';
  }

  bool? get _regionHintState {
    if (_isRegionCatalogLoading) return null;
    if (_selectedRegion == null || _selectedRegion!.trim().isEmpty) return null;
    return true;
  }

  String get _cityHintText {
    if (_isRegionCatalogLoading) {
      return 'سيتم تفعيل قائمة المدن بعد تحميل المناطق.';
    }
    final region = _activeRegion;
    if (region == null) {
      return 'بعد اختيار المنطقة ستظهر المدن التابعة لها هنا.';
    }
    if (_selectedCity == null || _selectedCity!.trim().isEmpty) {
      return 'اختر مدينة من المدن التابعة لمنطقة ${region.displayName}.';
    }
    return 'تم اختيار مدينة تابعة لمنطقة ${region.displayName}.';
  }

  bool? get _cityHintState {
    if (_selectedCity == null || _selectedCity!.trim().isEmpty) return null;
    return true;
  }

  String get _locationCalloutText {
    final region = _activeRegion;
    final city = _selectedCity?.trim() ?? '';
    if (_isRegionCatalogLoading) {
      return 'نجهز لك كتالوج المناطق والمدن الآن، لتكون البيانات الجغرافية أدق وأسهل في الاختيار.';
    }
    if (region == null) {
      return 'ابدأ باختيار المنطقة الإدارية ثم اختر المدينة التابعة لها، مثل: المنطقة = الرياض، المدينة = الخرج.';
    }
    if (city.isEmpty) {
      return 'تم تحديد منطقة ${region.displayName}. بقي اختيار المدينة التابعة لها لإكمال البيانات الجغرافية بصورة دقيقة.';
    }
    return 'الآن تم ربط المدينة $city ضمن منطقة ${region.displayName}، وبذلك أصبحت البيانات الجغرافية جاهزة بصورة أدق وأكثر اتساقًا.';
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _entranceController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadScreenContent() async {
    try {
      final result = await ContentService.fetchPublicContent();
      if (!mounted || !result.isSuccess || result.dataAsMap == null) return;
      final blocks =
          (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _content = SignupContent.fromBlocks(blocks);
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'SignUpScreen._loadScreenContent failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadRegionCatalog() async {
    if (mounted) {
      setState(() {
        _isRegionCatalogLoading = true;
        _usedRegionFallback = false;
      });
    }

    final result = await GeoCatalogService.fetchRegionCatalogWithFallback();
    final catalog = result.catalog;

    if (!mounted) return;
    setState(() {
      _regionCatalog = catalog;
      _isRegionCatalogLoading = false;
      _usedRegionFallback = result.usedFallback;
      if (_selectedRegion != null &&
          !catalog.any((region) =>
              region.nameAr == _selectedRegion ||
              region.displayName == _selectedRegion)) {
        _selectedRegion = null;
        _selectedCity = null;
      }
      if (_selectedCity != null &&
          !_availableCities.contains(_selectedCity)) {
        _selectedCity = null;
      }
    });
  }

  void _clearServerErrors() {
    if (_generalError == null && _fieldErrors == null) return;
    setState(() {
      _generalError = null;
      _fieldErrors = null;
    });
  }

  void _clearLocationErrors() {
    if (_regionError == null && _cityError == null) return;
    setState(() {
      _regionError = null;
      _cityError = null;
    });
  }

  bool _isValidUsernameChars(String value) {
    return RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(value);
  }

  void _onUsernameChanged(String value) {
    _clearServerErrors();
    _clearLocationErrors();

    final username = value.trim();
    _usernameDebounce?.cancel();

    setState(() {
      _isUsernameAvailable = null;
      _isCheckingUsername = false;
      _usernameHint = null;
    });

    if (username.isEmpty) return;
    if (username.length < 3) {
      setState(() {
        _isUsernameAvailable = false;
        _usernameHint = 'اسم المستخدم يجب أن يكون 3 أحرف على الأقل';
      });
      return;
    }
    if (!_isValidUsernameChars(username)) {
      setState(() {
        _isUsernameAvailable = false;
        _usernameHint = 'المسموح: حروف إنجليزية، أرقام، (_) و (.)';
      });
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability(username);
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    setState(() => _isCheckingUsername = true);

    final result = await AuthApiService.checkUsernameAvailability(username);
    if (!mounted) return;

    if (_usernameController.text.trim() != username) return;

    setState(() {
      _isCheckingUsername = false;
      _isUsernameAvailable = result.available;
      _usernameHint = result.message;
    });
  }

  void _onRegionChanged(String? value) {
    _clearServerErrors();
    _clearLocationErrors();
    setState(() {
      _selectedRegion = value;
      if (!_availableCities.contains(_selectedCity)) {
        _selectedCity = null;
      }
    });
  }

  void _onCityChanged(String? value) {
    _clearServerErrors();
    _clearLocationErrors();
    setState(() => _selectedCity = value);
  }

  Future<void> _onRegisterPressed() async {
    if ((_selectedRegion?.trim().isEmpty ?? true) ||
        (_selectedCity?.trim().isEmpty ?? true)) {
      setState(() {
        _regionError = (_selectedRegion?.trim().isEmpty ?? true)
            ? 'اختر المنطقة الإدارية'
            : null;
        _cityError = (_selectedCity?.trim().isEmpty ?? true)
            ? 'اختر المدينة التابعة للمنطقة'
            : null;
      });
      return;
    }

    if (!_isAllValid || _selectedCity == null) return;

    setState(() {
      _isLoading = true;
      _generalError = null;
      _fieldErrors = null;
      _regionError = null;
      _cityError = null;
    });

    final result = await AuthApiService.completeRegistration(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      city: _selectedCity!.trim(),
      password: _passwordController.text,
      passwordConfirm: _confirmPasswordController.text,
      acceptTerms: _agreeToTerms,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إكمال التسجيل بنجاح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.success,
        ),
      );

      if (widget.redirectTo != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => widget.redirectTo!),
          (route) => false,
        );
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
      return;
    }

    setState(() {
      _generalError = result.error;
      _fieldErrors = result.fieldErrors;
    });
  }

  Future<void> _onSkipPressed() async {
    if (_isLoading || _isSkipLoading) return;

    setState(() {
      _isSkipLoading = true;
      _generalError = null;
      _fieldErrors = null;
    });

    final result = await AuthApiService.skipCompletion();
    if (!mounted) return;

    setState(() => _isSkipLoading = false);

    if (result.success) {
      if (widget.redirectTo != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => widget.redirectTo!),
          (route) => false,
        );
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
      return;
    }

    setState(() {
      _generalError = result.error ?? 'تعذر تخطي إكمال البيانات';
    });
  }

  void _openTermsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? errorText,
    Widget? suffixIcon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      errorText: errorText,
      suffixIcon: suffixIcon,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: Color(0xFF655D7B),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: FaIcon(
          icon,
          size: 15,
          color: AppColors.deepPurple,
        ),
      ),
      filled: true,
      fillColor: const Color(0xFFFCFBFE),
      hintStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF9A93AF),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE6DFF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.deepPurple, width: 1.45),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.error, width: 1.35),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    void Function(String)? onChanged,
    String? errorText,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF201830),
      ),
      onChanged: onChanged ??
          (_) {
            _clearServerErrors();
            _clearLocationErrors();
            setState(() {});
          },
      decoration: _inputDecoration(
        label: label,
        icon: icon,
        errorText: errorText,
        suffixIcon: suffixIcon,
        hintText: hintText,
      ),
    );
  }

  Widget _buildUsernameStatusHint() {
    final backendError = _fieldErrors?['username'];
    if (backendError != null && backendError.isNotEmpty) {
      return _buildHintLine(
        backendError,
        tone: _HintTone.bad,
      );
    }

    if (_isCheckingUsername) {
      return _buildHintLine(
        'جاري التحقق من توفر اسم المستخدم...',
        tone: _HintTone.neutral,
        showSpinner: true,
      );
    }

    if (_usernameHint != null && _usernameHint!.isNotEmpty) {
      return _buildHintLine(
        _usernameHint!,
        tone: _isUsernameAvailable == true ? _HintTone.ok : _HintTone.bad,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildHintLine(
    String message, {
    required _HintTone tone,
    bool showSpinner = false,
  }) {
    Color color;
    switch (tone) {
      case _HintTone.ok:
        color = const Color(0xFF1B8A5A);
        break;
      case _HintTone.bad:
        color = const Color(0xFFBB4257);
        break;
      case _HintTone.neutral:
        color = const Color(0xFF7C748F);
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Padding(
        key: ValueKey('$message-$tone-$showSpinner'),
        padding: const EdgeInsets.only(top: 7, right: 4),
        child: Row(
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
                message,
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
      ),
    );
  }

  Widget? _buildUsernameSuffix() {
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isUsernameAvailable == true) {
      return const Icon(Icons.check_circle_rounded,
          color: AppColors.success, size: 20);
    }
    if (_isUsernameAvailable == false) {
      return const Icon(Icons.cancel_rounded,
          color: AppColors.error, size: 20);
    }
    return null;
  }

  Widget _buildCityDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCity,
      isExpanded: true,
      menuMaxHeight: 320,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF201830),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: _inputDecoration(
        label: 'المدينة',
        icon: FontAwesomeIcons.city,
        errorText: _cityError ?? _fieldErrors?['city'],
        hintText: _activeRegion == null ? 'اختر المنطقة أولًا' : 'اختر المدينة',
      ),
      items: _availableCities
          .map(
            (city) => DropdownMenuItem<String>(
              value: city,
              child: Text(
                city,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (_isLoading || _activeRegion == null) ? null : _onCityChanged,
    );
  }

  Widget _buildRegionDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedRegion,
      isExpanded: true,
      menuMaxHeight: 320,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF201830),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: _inputDecoration(
        label: 'المنطقة الإدارية',
        icon: FontAwesomeIcons.locationDot,
        errorText: _regionError,
        hintText:
            _isRegionCatalogLoading ? 'جاري تحميل المناطق...' : 'اختر المنطقة',
      ),
      items: _regionCatalog
          .map(
            (region) => DropdownMenuItem<String>(
              value: region.nameAr,
              child: Text(
                region.displayName,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          )
          .toList(),
      onChanged:
          (_isLoading || _isRegionCatalogLoading) ? null : _onRegionChanged,
    );
  }

  Widget _buildPasswordValidation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6FD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DCF6)),
      ),
      child: Wrap(
        runSpacing: 6,
        spacing: 10,
        children: [
          _buildValidationPill('8 أحرف+', _isPasswordValid),
          _buildValidationPill('حرف صغير', _hasLowercase),
          _buildValidationPill('حرف كبير', _hasUppercase),
          _buildValidationPill('رقم', _hasNumber),
          _buildValidationPill('رمز خاص', _hasSpecial),
        ],
      ),
    );
  }

  Widget _buildValidationPill(String text, bool valid) {
    final color = valid ? const Color(0xFF1B8A5A) : const Color(0xFF8C85A2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: valid ? const Color(0xFFECF8F2) : const Color(0xFFF3F0F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            valid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAFE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color:
              _agreeToTerms ? const Color(0xFFD7C7F0) : const Color(0xFFE8E0F4),
        ),
        boxShadow: _agreeToTerms
            ? [
                BoxShadow(
                  color: AppColors.deepPurple.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Checkbox(
            value: _agreeToTerms,
            visualDensity: VisualDensity.compact,
            activeColor: AppColors.deepPurple,
            onChanged: _isLoading
                ? null
                : (value) {
                    _clearServerErrors();
                    setState(() => _agreeToTerms = value ?? false);
                  },
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 1,
              children: [
                Text(
                  _content.termsLabelPrefix,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF534D6A),
                  ),
                ),
                GestureDetector(
                  onTap: _openTermsScreen,
                  child: Text(
                    _content.termsLabelLink,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepPurple,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
            colors: [Color(0xFFF8F4FF), Color(0xFFFDFBFE), Color(0xFFF7FBFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _buildEntrance(0, _buildFormCard()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildShowcaseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF2D185A), Color(0xFF4E2F97)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D185A).withValues(alpha: 0.18),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            left: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -46,
            right: -20,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD2A14C).withValues(alpha: 0.18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadge(
                label: 'مسار تسجيل أنيق وواضح',
                dark: true,
              ),
              const SizedBox(height: 14),
              const Text(
                'أكمل حضورك الأول داخل نوافذ بصورة أكثر احترافية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 21,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'الواجهة هنا مصممة لتجعل الإكمال أسرع وأوضح، مع تنظيم أفضل للمعلومات الأساسية واختيار جغرافي متوافق مع النظام عبر المنطقة الإدارية ثم المدينة التابعة لها.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
              const SizedBox(height: 14),
              _buildShowcasePoint(
                  'بيانات أساسية منظمة تمنح الحساب انطلاقة أنظف وأكثر ثقة.'),
              const SizedBox(height: 8),
              _buildShowcasePoint(
                  'اختيار جغرافي مرحلي: المنطقة أولًا ثم المدينة التابعة لها.'),
              const SizedBox(height: 8),
              _buildShowcasePoint(
                  'تلميحات واضحة أثناء الكتابة للتحقق من اسم المستخدم وكلمة المرور.'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _SignupShowcaseTag(label: 'مظهر فاخر وناعم'),
                  _SignupShowcaseTag(label: 'متوافق مع الجوال'),
                  _SignupShowcaseTag(label: 'اختيار منطقة ثم مدينة'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── HERO HEADER ─────────────────────────────────────────────────────────────

  Widget _buildHeroHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E0E42), Color(0xFF3C216F), Color(0xFF5433A8)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Decorative blurred circles
            Positioned(
              top: -36,
              left: -36,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              right: -30,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF9B6DFF).withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 60,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD2A14C).withValues(alpha: 0.12),
                ),
              ),
            ),
            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: const Text(
                        'إكمال التسجيل',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFFF5D8),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD2A14C).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'نوافذ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFFD98A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _content.title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 24,
                    height: 1.3,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _content.description,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    height: 1.85,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 18),
                // Step progress indicators
                Row(
                  children: [
                    _buildHeroStep('01', 'بيانات شخصية', true),
                    _buildHeroStepLine(),
                    _buildHeroStep('02', 'الموقع', false),
                    _buildHeroStepLine(),
                    _buildHeroStep('03', 'كلمة المرور', false),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStep(String num, String label, bool active) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0xFFD2A14C)
                : Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: active
                  ? const Color(0xFFD2A14C)
                  : Colors.white.withValues(alpha: 0.22),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              num,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: active
                    ? const Color(0xFF1E0E42)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: active
                ? const Color(0xFFFFD98A)
                : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroStepLine() {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 22, left: 6, right: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  // ─── SECTION HELPERS ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String step,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFF3C216F), Color(0xFF6941C6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3C216F).withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: FaIcon(icon, size: 15, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F1738),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1EAFE),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Color(0xFF4D2997),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x00E8DFF4), Color(0xFFE8DFF4), Color(0x00E8DFF4)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      key: ValueKey(error),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFBB4257).withValues(alpha: 0.2),
        ),
        color: const Color(0xFFFFF1F4),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: Color(0xFFBB4257)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFBB4257),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── ACTION BUTTONS ───────────────────────────────────────────────────────────

  Widget _buildPrimaryButton({bool fullWidth = true}) {
    final enabled = _isAllValid && !_isLoading && !_isSkipLoading;
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF3C216F), Color(0xFF6941C6)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                )
              : null,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF3C216F).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: enabled ? _onRegisterPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                enabled ? Colors.transparent : AppColors.deepPurple.withValues(alpha: 0.38),
            disabledBackgroundColor:
                AppColors.deepPurple.withValues(alpha: 0.38),
            shadowColor: Colors.transparent,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
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
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 17, color: Colors.white),
                    const SizedBox(width: 7),
                    Text(
                      _content.submitLabel,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSkipButton({required bool wide}) {
    return SizedBox(
      width: wide ? double.infinity : null,
      child: OutlinedButton.icon(
        onPressed: (_isLoading || _isSkipLoading) ? null : _onSkipPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4D2997),
          backgroundColor: const Color(0xFFF4EEFE),
          side: const BorderSide(color: Color(0xFFD8C7F2)),
          padding: EdgeInsets.symmetric(
            vertical: 14,
            horizontal: wide ? 0 : 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        icon: _isSkipLoading
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: Color(0xFF4D2997)),
              )
            : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
        label: Text(
          _isSkipLoading ? 'جارٍ التخطي...' : 'تخطي',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ─── FORM CARD (no outer card — open layout) ──────────────────────────────────

  Widget _buildFormCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 430;
        final stackActions = constraints.maxWidth < 540;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero header ─────────────────────────────────────────────────
            _buildHeroHeader(),
            const SizedBox(height: 24),

            // ── Error banner ─────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _generalError == null
                  ? const SizedBox.shrink()
                  : _buildErrorBanner(_generalError!),
            ),
            if (_generalError != null) const SizedBox(height: 16),

            // ══ SECTION 01 — البيانات الشخصية ═══════════════════════════════
            _buildSectionHeader(
              icon: FontAwesomeIcons.userPen,
              title: 'البيانات الشخصية',
              step: '01',
            ),
            const SizedBox(height: 14),
            _buildAdaptiveTwoColumn(
              isWide: isWide,
              first: _buildTextField(
                label: 'الاسم الأول',
                controller: _firstNameController,
                icon: FontAwesomeIcons.user,
                hintText: 'مثال: خالد',
                errorText: _fieldErrors?['first_name'],
              ),
              second: _buildTextField(
                label: 'الاسم الأخير',
                controller: _lastNameController,
                icon: FontAwesomeIcons.user,
                hintText: 'مثال: العتيبي',
                errorText: _fieldErrors?['last_name'],
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: 'اسم المستخدم',
              controller: _usernameController,
              icon: FontAwesomeIcons.at,
              hintText: 'username.example',
              suffixIcon: _buildUsernameSuffix(),
              onChanged: _onUsernameChanged,
              errorText: _fieldErrors?['username'],
            ),
            _buildUsernameStatusHint(),
            const SizedBox(height: 12),
            _buildTextField(
              label: 'البريد الإلكتروني',
              controller: _emailController,
              icon: FontAwesomeIcons.envelope,
              hintText: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              errorText: _fieldErrors?['email'],
            ),
            const SizedBox(height: 22),
            _buildSectionDivider(),
            const SizedBox(height: 22),

            // ══ SECTION 02 — الموقع الجغرافي ════════════════════════════════
            _buildSectionHeader(
              icon: FontAwesomeIcons.locationDot,
              title: 'الموقع الجغرافي',
              step: '02',
            ),
            const SizedBox(height: 14),
            _buildLocationCallout(),
            const SizedBox(height: 12),
            _buildAdaptiveTwoColumn(
              isWide: isWide,
              first: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRegionDropdown(),
                  _buildHintLine(
                    _regionHintText,
                    tone: _regionHintState == true
                        ? _HintTone.ok
                        : _HintTone.neutral,
                  ),
                ],
              ),
              second: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCityDropdown(),
                  _buildHintLine(
                    _cityHintText,
                    tone: _cityHintState == true
                        ? _HintTone.ok
                        : _HintTone.neutral,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _buildSectionDivider(),
            const SizedBox(height: 22),

            // ══ SECTION 03 — كلمة المرور والأمان ════════════════════════════
            _buildSectionHeader(
              icon: FontAwesomeIcons.shieldHalved,
              title: 'كلمة المرور والأمان',
              step: '03',
            ),
            const SizedBox(height: 14),
            _buildAdaptiveTwoColumn(
              isWide: isWide,
              first: _buildTextField(
                label: 'كلمة المرور',
                controller: _passwordController,
                icon: FontAwesomeIcons.lock,
                hintText: '••••••••',
                obscure: _obscurePassword,
                errorText: _fieldErrors?['password'],
                onChanged: (_) {
                  _clearServerErrors();
                  _clearLocationErrors();
                  setState(() {});
                },
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              second: _buildTextField(
                label: 'تأكيد كلمة المرور',
                controller: _confirmPasswordController,
                icon: FontAwesomeIcons.lockOpen,
                hintText: '••••••••',
                obscure: _obscureConfirmPassword,
                errorText: _fieldErrors?['password_confirm'],
                onChanged: (_) {
                  _clearServerErrors();
                  _clearLocationErrors();
                  setState(() {});
                },
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  onPressed: () {
                    setState(
                      () =>
                          _obscureConfirmPassword = !_obscureConfirmPassword,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildPasswordValidation(),
            const SizedBox(height: 22),
            _buildSectionDivider(),
            const SizedBox(height: 18),

            // ── Terms ─────────────────────────────────────────────────────────
            _buildTermsSection(),
            if (_fieldErrors?['accept_terms'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Text(
                  _fieldErrors!['accept_terms']!,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFBB4257),
                  ),
                ),
              ),
            const SizedBox(height: 22),

            // ── Action buttons ────────────────────────────────────────────────
            if (stackActions) ...[
              _buildPrimaryButton(),
              const SizedBox(height: 10),
              _buildSkipButton(wide: true),
            ] else ...[
              Row(
                children: [
                  Expanded(child: _buildPrimaryButton()),
                  const SizedBox(width: 10),
                  _buildSkipButton(wide: false),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'يمكنك إكمال البيانات لاحقًا، وسيبقى الحساب مفعّلًا برقم الجوال.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                height: 1.8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9089A8),
              ),
            ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Widget _buildAdaptiveTwoColumn({
    required bool isWide,
    required Widget first,
    required Widget second,
  }) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    }
    return Column(
      children: [
        first,
        const SizedBox(height: 12),
        second,
      ],
    );
  }

  Widget _buildLocationCallout() {
    final isReady = _selectedCity?.trim().isNotEmpty == true;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isReady ? const Color(0xFFD8C7F0) : const Color(0xFFE8DFF4),
        ),
        gradient: LinearGradient(
          colors: isReady
              ? const [Color(0xFFFFFFFF), Color(0xFFF4FAF7)]
              : const [Color(0xFFFFFFFF), Color(0xFFF7F3FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: isReady
            ? [
                BoxShadow(
                  color: AppColors.deepPurple.withValues(alpha: 0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: isReady
                    ? const [Color(0xFF1B8A5A), Color(0xFF49BFD2)]
                    : const [Color(0xFF4D2997), Color(0xFF7A4FD1)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختيار جغرافي متدرج',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F1738),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _locationCalloutText,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    height: 1.8,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF625C79),
                  ),
                ),
                if (_isRegionCatalogLoading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 5,
                      color: Color(0xFF7A4FD1),
                      backgroundColor: Color(0xFFECE4F8),
                    ),
                  ),
                ],
                if (_usedRegionFallback && !_isRegionCatalogLoading) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'تم الاعتماد مؤقتًا على الكتالوج الاحتياطي للمناطق والمدن.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7B6F95),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSideCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7DDF5)),
        color: const Color(0xFFFCFBFE),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBadge(label: 'تجربة أوضح'),
          const SizedBox(height: 10),
          const Text(
            'ما الذي يجعل هذه الصفحة أفضل؟',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F1738),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'الهدف هنا ليس فقط إكمال التسجيل، بل إكماله بصورة مرتبة ومريحة تمنح المستخدم انطباعًا قويًا من البداية.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.85,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5F5977),
            ),
          ),
          const SizedBox(height: 10),
          _buildSideListItem('كل حقل له مساحة أوضح وتلميح أقرب للفهم.'),
          const SizedBox(height: 8),
          _buildSideListItem(
              'اختيار المنطقة ثم المدينة يمنع الالتباس ويجعل الإدخال أدق.'),
          const SizedBox(height: 8),
          _buildSideListItem('التصميم متوازن على الشاشات الصغيرة بنفس الجودة.'),
        ],
      ),
    );
  }

  // ignore: unused_element
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

  Widget _buildShowcasePoint(String text) {
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
              height: 1.85,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideListItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF4D2997), Color(0xFF49BFD2)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepPurple.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.check, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              height: 1.8,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4F4965),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge({required String label, bool dark = false}) {
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

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.08 * index).clamp(0.0, 0.82).toDouble();
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

enum _HintTone { neutral, ok, bad }

class SignupContent {
  final String title;
  final String description;
  final String submitLabel;
  final String termsLabelPrefix;
  final String termsLabelLink;

  const SignupContent({
    required this.title,
    required this.description,
    required this.submitLabel,
    required this.termsLabelPrefix,
    required this.termsLabelLink,
  });

  factory SignupContent.defaults() {
    return const SignupContent(
      title: 'إكمال التسجيل',
      description:
          'أكمل بياناتك مرة واحدة لتفعيل الحساب والانتقال مباشرة إلى المنصة.',
      submitLabel: 'إكمال التسجيل',
      termsLabelPrefix: 'أوافق على',
      termsLabelLink: 'الشروط والأحكام',
    );
  }

  factory SignupContent.fromBlocks(Map<String, dynamic> blocks) {
    String resolve(String key, String fallback) {
      final block = blocks[key];
      if (block is! Map<String, dynamic>) return fallback;
      final title = (block['title_ar'] as String?)?.trim() ?? '';
      return title.isNotEmpty ? title : fallback;
    }

    final terms = resolve('signup_terms_label', 'أوافق على الشروط والأحكام');
    const link = 'الشروط والأحكام';
    final prefix = terms.endsWith(link)
        ? terms.substring(0, terms.length - link.length).trim()
        : terms;

    return SignupContent(
      title: resolve('signup_title', 'إكمال التسجيل'),
      description: resolve(
        'signup_description',
        'أكمل بياناتك مرة واحدة لتفعيل الحساب والانتقال مباشرة إلى المنصة.',
      ),
      submitLabel: resolve('signup_submit_label', 'إكمال التسجيل'),
      termsLabelPrefix: prefix.isNotEmpty ? prefix : 'أوافق على',
      termsLabelLink: link,
    );
  }
}

class _SignupShowcaseTag extends StatelessWidget {
  final String label;

  const _SignupShowcaseTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFFF8F4FF),
        ),
      ),
    );
  }
}
