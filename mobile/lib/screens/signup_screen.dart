import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../constants/colors.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/app_bar.dart';
import '../services/auth_api_service.dart';
import 'terms_screen.dart';

class SignUpScreen extends StatefulWidget {
  /// الشاشة الوجهة بعد إتمام التسجيل (اختياري)
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
  final _cityController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _agreeToTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _generalError;
  Map<String, String>? _fieldErrors;

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
      _cityController.text.trim().isNotEmpty &&
      _passwordController.text == _confirmPasswordController.text &&
      _isPasswordValid &&
      _hasLowercase &&
      _hasUppercase &&
      _hasNumber &&
      _hasSpecial &&
      _agreeToTerms;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// ✅ إكمال التسجيل عبر الـ API
  Future<void> _onRegisterPressed() async {
    if (!_isAllValid) return;

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
      city: _cityController.text.trim(),
      password: _passwordController.text,
      passwordConfirm: _confirmPasswordController.text,
      acceptTerms: _agreeToTerms,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      // عرض رسالة نجاح
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ تم إكمال التسجيل بنجاح",
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
        ),
      );

      // التوجيه
      if (widget.redirectTo != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => widget.redirectTo!),
          (route) => false,
        );
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } else {
      setState(() {
        _generalError = result.error;
        _fieldErrors = result.fieldErrors;
      });
    }
  }

  void _openTermsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 430;

    return Scaffold(
      drawer: const CustomDrawer(),
      appBar: const CustomAppBar(title: "إكمال البيانات"),
      backgroundColor: const Color(0xFFF2F3F5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFFF0EAFE), Color(0xFFFFFFFF)],
                    ),
                    border: Border.all(
                      color: AppColors.deepPurple.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        "أكمل بياناتك لتفعيل حسابك",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          color: AppColors.deepPurple,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "هذه البيانات مطلوبة لمرة واحدة فقط",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Cairo',
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                if (_generalError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _generalError!,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (isWide)
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(
                          "الاسم الأول",
                          _firstNameController,
                          FontAwesomeIcons.user,
                          errorText: _fieldErrors?['first_name'],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildField(
                          "الاسم الأخير",
                          _lastNameController,
                          FontAwesomeIcons.user,
                          errorText: _fieldErrors?['last_name'],
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildField(
                    "الاسم الأول",
                    _firstNameController,
                    FontAwesomeIcons.user,
                    errorText: _fieldErrors?['first_name'],
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    "الاسم الأخير",
                    _lastNameController,
                    FontAwesomeIcons.user,
                    errorText: _fieldErrors?['last_name'],
                  ),
                ],
                const SizedBox(height: 14),

                _buildField(
                  "اسم المستخدم",
                  _usernameController,
                  FontAwesomeIcons.at,
                  errorText: _fieldErrors?['username'],
                ),
                const SizedBox(height: 14),

                _buildField(
                  "البريد الإلكتروني",
                  _emailController,
                  FontAwesomeIcons.envelope,
                  keyboardType: TextInputType.emailAddress,
                  errorText: _fieldErrors?['email'],
                ),
                const SizedBox(height: 14),

                _buildField(
                  "المدينة",
                  _cityController,
                  FontAwesomeIcons.city,
                  errorText: _fieldErrors?['city'],
                ),
                const SizedBox(height: 14),

                _buildField(
                  "كلمة المرور",
                  _passwordController,
                  FontAwesomeIcons.lock,
                  obscure: _obscurePassword,
                  onChanged: (_) => setState(() {}),
                  errorText: _fieldErrors?['password'],
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildPasswordValidation(),
                const SizedBox(height: 14),

                _buildField(
                  "تأكيد كلمة المرور",
                  _confirmPasswordController,
                  FontAwesomeIcons.lockOpen,
                  obscure: _obscureConfirmPassword,
                  errorText: _fieldErrors?['password_confirm'],
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _agreeToTerms,
                        onChanged: (val) {
                          setState(() => _agreeToTerms = val ?? false);
                        },
                        activeColor: AppColors.deepPurple,
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              "أوافق على",
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            GestureDetector(
                              onTap: _openTermsScreen,
                              child: const Text(
                                "الشروط والأحكام",
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  color: AppColors.deepPurple,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_fieldErrors?['accept_terms'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _fieldErrors!['accept_terms']!,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                if (!_agreeToTerms)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      "يجب الموافقة على الشروط والأحكام للمتابعة",
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),

                ElevatedButton(
                  onPressed:
                      (_isAllValid && !_isLoading) ? _onRegisterPressed : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepPurple,
                    disabledBackgroundColor: AppColors.deepPurple.withValues(
                      alpha: 0.45,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "إكمال التسجيل",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            color: Colors.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onChanged: onChanged ?? (_) => setState(() {
        _generalError = null;
        _fieldErrors = null;
      }),
      style: const TextStyle(fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo'),
        suffixIcon: suffixIcon,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FaIcon(icon, size: 20, color: AppColors.deepPurple),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDADCE0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDADCE0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.deepPurple, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 14,
        ),
        errorText: errorText,
        errorStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
      ),
    );
  }

  Widget _buildPasswordValidation() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildValidationRow("8 أحرف أو أكثر", _isPasswordValid),
          _buildValidationRow("حرف صغير", _hasLowercase),
          _buildValidationRow("حرف كبير", _hasUppercase),
          _buildValidationRow("رقم", _hasNumber),
          _buildValidationRow("رمز خاص", _hasSpecial),
        ],
      ),
    );
  }

  Widget _buildValidationRow(String text, bool valid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: valid ? Colors.green : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Cairo',
              color: valid ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
