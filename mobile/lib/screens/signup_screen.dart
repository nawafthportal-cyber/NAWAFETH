import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../constants/colors.dart';
import '../constants/saudi_cities.dart';
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

class _SignUpScreenState extends State<SignUpScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Timer? _usernameDebounce;

  String? _selectedCity;
  bool _agreeToTerms = false;
  bool _isLoading = false;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameHint;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _generalError;
  Map<String, String>? _fieldErrors;
  SignupContent _content = SignupContent.defaults();

  @override
  void initState() {
    super.initState();
    _loadScreenContent();
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
      (_selectedCity?.isNotEmpty ?? false) &&
      _passwordController.text == _confirmPasswordController.text &&
      _isPasswordValid &&
      _hasLowercase &&
      _hasUppercase &&
      _hasNumber &&
      _hasSpecial &&
      (_isUsernameAvailable == true) &&
      !_isCheckingUsername &&
      _agreeToTerms;

  @override
  void dispose() {
    _usernameDebounce?.cancel();
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

  void _clearServerErrors() {
    if (_generalError == null && _fieldErrors == null) return;
    setState(() {
      _generalError = null;
      _fieldErrors = null;
    });
  }

  bool _isValidUsernameChars(String value) {
    return RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(value);
  }

  void _onUsernameChanged(String value) {
    _clearServerErrors();

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

  Future<void> _onRegisterPressed() async {
    if (!_isAllValid || _selectedCity == null) return;

    setState(() {
      _isLoading = true;
      _generalError = null;
      _fieldErrors = null;
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
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      suffixIcon: suffixIcon,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        color: Colors.black54,
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11.5,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: FaIcon(
          icon,
          size: 16,
          color: AppColors.deepPurple,
        ),
      ),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9DCE3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.deepPurple, width: 1.35),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 14,
      ),
      onChanged: onChanged ??
          (_) {
            _clearServerErrors();
            setState(() {});
          },
      decoration: _inputDecoration(
        label: label,
        icon: icon,
        errorText: errorText,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildUsernameStatusHint() {
    final backendError = _fieldErrors?['username'];
    if (backendError != null && backendError.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, right: 4),
        child: Text(
          backendError,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            color: Colors.red,
          ),
        ),
      );
    }

    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, right: 4),
        child: Text(
          'جاري التحقق من توفر اسم المستخدم...',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            color: Colors.black54,
          ),
        ),
      );
    }

    if (_usernameHint != null && _usernameHint!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, right: 4),
        child: Text(
          _usernameHint!,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            color: _isUsernameAvailable == true ? Colors.green : Colors.red,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
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
        fontSize: 14,
        color: Colors.black87,
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: _inputDecoration(
        label: 'المدينة',
        icon: FontAwesomeIcons.city,
        errorText: _fieldErrors?['city'],
      ),
      items: SaudiCities.all
          .map(
            (city) => DropdownMenuItem<String>(
              value: city,
              child: Text(
                city,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
            ),
          )
          .toList(),
      onChanged: _isLoading
          ? null
          : (value) {
              _clearServerErrors();
              setState(() => _selectedCity = value);
            },
    );
  }

  Widget _buildPasswordValidation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9EAF0)),
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
    final color = valid ? Colors.green : Colors.grey.shade500;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          valid ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTermsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
                    fontSize: 12.5,
                    color: Colors.black87,
                  ),
                ),
                GestureDetector(
                  onTap: _openTermsScreen,
                  child: Text(
                    _content.termsLabelLink,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.045),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _content.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _content.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_generalError != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _generalError!,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 390) {
                          return Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  label: 'الاسم الأول',
                                  controller: _firstNameController,
                                  icon: FontAwesomeIcons.user,
                                  errorText: _fieldErrors?['first_name'],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildTextField(
                                  label: 'الاسم الأخير',
                                  controller: _lastNameController,
                                  icon: FontAwesomeIcons.user,
                                  errorText: _fieldErrors?['last_name'],
                                ),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _buildTextField(
                              label: 'الاسم الأول',
                              controller: _firstNameController,
                              icon: FontAwesomeIcons.user,
                              errorText: _fieldErrors?['first_name'],
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              label: 'الاسم الأخير',
                              controller: _lastNameController,
                              icon: FontAwesomeIcons.user,
                              errorText: _fieldErrors?['last_name'],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),

                    _buildTextField(
                      label: 'اسم المستخدم',
                      controller: _usernameController,
                      icon: FontAwesomeIcons.at,
                      suffixIcon: _buildUsernameSuffix(),
                      onChanged: _onUsernameChanged,
                    ),
                    _buildUsernameStatusHint(),
                    const SizedBox(height: 10),

                    _buildTextField(
                      label: 'البريد الإلكتروني',
                      controller: _emailController,
                      icon: FontAwesomeIcons.envelope,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _fieldErrors?['email'],
                    ),
                    const SizedBox(height: 10),

                    _buildCityDropdown(),
                    const SizedBox(height: 10),

                    _buildTextField(
                      label: 'كلمة المرور',
                      controller: _passwordController,
                      icon: FontAwesomeIcons.lock,
                      obscure: _obscurePassword,
                      errorText: _fieldErrors?['password'],
                      onChanged: (_) {
                        _clearServerErrors();
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
                    const SizedBox(height: 7),
                    _buildPasswordValidation(),
                    const SizedBox(height: 10),

                    _buildTextField(
                      label: 'تأكيد كلمة المرور',
                      controller: _confirmPasswordController,
                      icon: FontAwesomeIcons.lockOpen,
                      obscure: _obscureConfirmPassword,
                      errorText: _fieldErrors?['password_confirm'],
                      onChanged: (_) {
                        _clearServerErrors();
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
                    const SizedBox(height: 12),

                    _buildTermsSection(),
                    if (_fieldErrors?['accept_terms'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: 4),
                        child: Text(
                          _fieldErrors!['accept_terms']!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            color: Colors.red,
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed:
                          (_isAllValid && !_isLoading) ? _onRegisterPressed : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepPurple,
                        disabledBackgroundColor: AppColors.deepPurple.withValues(
                          alpha: 0.42,
                        ),
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
