import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../constants/colors.dart';
import '../constants/saudi_cities.dart';
import '../services/api_client.dart';
import '../services/auth_api_service.dart';
import '../services/content_service.dart';
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
      final blocks = (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _content = SignupContent.fromBlocks(blocks);
      });
    } catch (_) {}
  }

  Future<void> _loadRegionCatalog() async {
    if (mounted) {
      setState(() {
        _isRegionCatalogLoading = true;
        _usedRegionFallback = false;
      });
    }

    try {
      final response = await ApiClient.get('/api/providers/geo/regions-cities/');
      final parsed = _normalizeRegionCatalog(response.data);
      final catalog = parsed.isNotEmpty
          ? parsed
          : List<SaudiRegionCatalogEntry>.from(SaudiCities.regionCatalogFallback);

      if (!mounted) return;
      setState(() {
        _regionCatalog = catalog;
        _isRegionCatalogLoading = false;
        _usedRegionFallback = parsed.isEmpty;
        if (_selectedRegion != null &&
            !catalog.any((region) =>
                region.nameAr == _selectedRegion ||
                region.displayName == _selectedRegion)) {
          _selectedRegion = null;
          _selectedCity = null;
        }
        if (_selectedCity != null && !_availableCities.contains(_selectedCity)) {
          _selectedCity = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _regionCatalog = List<SaudiRegionCatalogEntry>.from(
          SaudiCities.regionCatalogFallback,
        );
        _isRegionCatalogLoading = false;
        _usedRegionFallback = true;
      });
    }
  }

  List<SaudiRegionCatalogEntry> _normalizeRegionCatalog(dynamic data) {
    final rows = data is List
        ? data
        : (data is Map<String, dynamic> && data['results'] is List)
            ? data['results'] as List
            : const [];

    final normalized = <SaudiRegionCatalogEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final item = Map<String, dynamic>.from(row);
      final rawName = _extractDisplayValue(item, const ['name_ar', 'name', 'region']);
      final rawCities = item['cities'];
      if (rawName.isEmpty || rawCities is! List) continue;

      final cities = rawCities
          .map((city) {
            if (city is String) return city.trim();
            if (city is Map) {
              return _extractDisplayValue(
                Map<String, dynamic>.from(city),
                const ['name_ar', 'name', 'city'],
              );
            }
            return '';
          })
          .where((city) => city.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (cities.isEmpty) continue;
      normalized.add(SaudiRegionCatalogEntry(nameAr: rawName, cities: cities));
    }

    normalized.sort((left, right) => left.displayName.compareTo(right.displayName));
    return normalized;
  }

  String _extractDisplayValue(
    Map<String, dynamic> item,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
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
          backgroundColor: Colors.green,
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
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.35),
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
      return const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20);
    }
    if (_isUsernameAvailable == false) {
      return const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 20);
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
        hintText: _isRegionCatalogLoading ? 'جاري تحميل المناطق...' : 'اختر المنطقة',
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
      onChanged: (_isLoading || _isRegionCatalogLoading) ? null : _onRegionChanged,
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
        color: valid
            ? const Color(0xFFECF8F2)
            : const Color(0xFFF3F0F8),
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
          color: _agreeToTerms
              ? const Color(0xFFD7C7F0)
              : const Color(0xFFE8E0F4),
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
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    _buildEntrance(0, _buildShowcaseCard()),
                    const SizedBox(height: 14),
                    _buildEntrance(1, _buildFormCard()),
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
              _buildShowcasePoint('بيانات أساسية منظمة تمنح الحساب انطلاقة أنظف وأكثر ثقة.'),
              const SizedBox(height: 8),
              _buildShowcasePoint('اختيار جغرافي مرحلي: المنطقة أولًا ثم المدينة التابعة لها.'),
              const SizedBox(height: 8),
              _buildShowcasePoint('تلميحات واضحة أثناء الكتابة للتحقق من اسم المستخدم وكلمة المرور.'),
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

  Widget _buildFormCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 430;
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
              Text(
                _content.title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F1738),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _content.description,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6F6987),
                ),
              ),
              const SizedBox(height: 14),
              _buildSoftPanel(
                icon: Icons.auto_awesome_rounded,
                title: 'تهيئة أكثر وضوحًا',
                body:
                    'نجهز بيانات الحساب بخطوات مرتبة ومقروءة على الجوال، دون تضخيم للحجم أو ازدحام بصري.',
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _generalError == null
                    ? const SizedBox(height: 0)
                    : Container(
                        key: ValueKey(_generalError),
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFBB4257).withValues(alpha: 0.18),
                          ),
                          color: const Color(0xFFFFF1F4),
                        ),
                        child: Text(
                          _generalError!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFBB4257),
                          ),
                        ),
                      ),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
                        () => _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildPasswordValidation(),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_isAllValid && !_isLoading) ? _onRegisterPressed : null,
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
              const SizedBox(height: 14),
              _buildSideCard(),
            ],
          ),
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
          color: isReady
              ? const Color(0xFFD8C7F0)
              : const Color(0xFFE8DFF4),
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
          _buildSideListItem('اختيار المنطقة ثم المدينة يمنع الالتباس ويجعل الإدخال أدق.'),
          const SizedBox(height: 8),
          _buildSideListItem('التصميم متوازن على الشاشات الصغيرة بنفس الجودة.'),
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
      description: 'أكمل بياناتك مرة واحدة لتفعيل الحساب والانتقال مباشرة إلى المنصة.',
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
