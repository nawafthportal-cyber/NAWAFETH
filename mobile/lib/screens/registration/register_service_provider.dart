import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nawafeth/services/account_mode_service.dart';

// استيراد الخطوات
import 'steps/personal_info_step.dart';
import 'steps/service_classification_step.dart';
import 'steps/contact_info_step.dart';

// لوحة المزود بعد التسجيل
import '../provider_dashboard/provider_home_screen.dart';

class RegisterServiceProviderPage extends StatefulWidget {
  const RegisterServiceProviderPage({super.key});

  @override
  State<RegisterServiceProviderPage> createState() =>
      _RegisterServiceProviderPageState();
}

class _RegisterServiceProviderPageState
    extends State<RegisterServiceProviderPage>
    with SingleTickerProviderStateMixin {
  final List<String> stepTitles = [
    'المعلومات الأساسية',
    'تصنيف الاختصاص',
    'بيانات التواصل',
  ];

  int _currentStep = 0;
  late ScrollController _scrollController;
  late AnimationController _animationController;

  bool _showSuccessOverlay = false;
  
  // تتبع نسبة إكمال كل صفحة (من 0.0 إلى 1.0)
  Map<int, double> _stepCompletion = {
    0: 0.0, // المعلومات الأساسية
    1: 0.0, // تصنيف الاختصاص
    2: 0.0, // بيانات التواصل
  };

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
    if (_currentStep < stepTitles.length - 1) {
      setState(() {
        _currentStep++;
        _animationController.forward(from: 0);
      });
      _scrollToCurrentStep();
    }
  }

  void _goToPreviousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _animationController.forward(from: 0);
      });
      _scrollToCurrentStep();
    }
  }

  void _scrollToCurrentStep() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      final screenWidth =
          box?.constraints.maxWidth ?? MediaQuery.of(context).size.width;
      const itemWidth = 120.0;
      final offset =
          (_currentStep * itemWidth) - (screenWidth / 2 - itemWidth / 2);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          offset.clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _updateStepCompletion(int step, double completionPercent) {
    setState(() {
      _stepCompletion[step] = completionPercent.clamp(0.0, 1.0);
    });
  }

  void _completeRegistration() {
    setState(() {
      _showSuccessOverlay = true;
    });
  }

  double get _completionPercent {
    // حساب مجموع نسب إكمال جميع الصفحات
    double totalCompletion = _stepCompletion.values.reduce((a, b) => a + b);
    // القسمة على عدد الصفحات للحصول على النسبة الإجمالية
    return totalCompletion / stepTitles.length;
  }

  Widget _buildStepItem(String title, int index) {
    final bool isActive = index == _currentStep;
    final bool isCompleted = index < _currentStep;

    final Color activeColor = Colors.deepPurple;
    final Color completedColor = Colors.green;
    final Color circleColor =
        isCompleted
            ? completedColor
            : (isActive ? activeColor : Colors.grey.shade300);
    final Color iconColor =
        isActive || isCompleted ? Colors.white : Colors.black87;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: isActive ? 34 : 30,
          height: isActive ? 34 : 30,
          decoration: BoxDecoration(
            color: circleColor,
            shape: BoxShape.circle,
            boxShadow:
                isActive
                    ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                    : [],
          ),
          child: Center(
            child: Icon(
              isCompleted ? Icons.check : Icons.circle,
              size: isCompleted ? 18 : 10,
              color: iconColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 110,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: Colors.white,
              fontFamily: 'Cairo',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // شريط علوي
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      "التسجيل كمقدم خدمة",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

            // مؤشرات الخطوات
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SizedBox(
                height: 74,
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: stepTitles.length,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder:
                      (context, index) =>
                          _buildStepItem(stepTitles[index], index),
                ),
              ),
            ),

            // شريط التقدم + نص بسيط
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: LinearProgressIndicator(
                            value: _completionPercent,
                            minHeight: 6,
                            backgroundColor: Colors.white.withOpacity(0.25),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "${(_completionPercent * 100).round()}%",
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "ثلاث خطوات بسيطة لإنشاء حسابك المبدئي.",
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    final steps = [
      PersonalInfoStep(
        onNext: _goToNextStep,
        onValidationChanged: (percent) => _updateStepCompletion(0, percent),
      ),
      ServiceClassificationStep(
        onNext: _goToNextStep,
        onBack: _goToPreviousStep,
        onValidationChanged: (percent) => _updateStepCompletion(1, percent),
      ),
      ContactInfoStep(
        onNext: _completeRegistration,
        onBack: _goToPreviousStep,
        isInitialRegistration: true,
        isFinalStep: true,
        onValidationChanged: (percent) => _updateStepCompletion(2, percent),
      ),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.05, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: steps[_currentStep],
    );
  }

  Widget _buildSuccessCard(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الأيقونة
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  "🎉 تم إنشاء حسابك بنجاح",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                // نسبة إكمال الملف الشخصي (30% فقط بعد التسجيل)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_circle_outlined,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "نسبة إكمال الملف: %30",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo',
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "تم تسجيلك كمزود خدمة لدى تطبيق نوافذ.\nأصبح لديك الآن حساب كمقدم خدمة، يمكنك إكمال ملفك التعريفي لتحسين ظهورك أمام العملاء.",
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'Cairo',
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F4FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.deepPurple.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    children: const [
                      _SuccessHintRow(
                        icon: Icons.person_outline,
                        text: "أضف تفاصيل أكثر عنك وعن خبراتك.",
                      ),
                      SizedBox(height: 4),
                      _SuccessHintRow(
                        icon: Icons.home_repair_service_outlined,
                        text: "عرّف بخدماتك وأعمالك السابقة.",
                      ),
                      SizedBox(height: 4),
                      _SuccessHintRow(
                        icon: Icons.language_outlined,
                        text: "حدّد لغاتك وموقعك الجغرافي.",
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // زر الانتقال للوحة المزود (سأكمل الآن)
                ElevatedButton(
                  onPressed: () async {
                    // ✅ حفظ نوع المستخدم كمقدم خدمة
                    final prefs = await SharedPreferences.getInstance();
                    await AccountModeService.setProviderMode(true);
                    await prefs.setBool('isProviderRegistered', true);
                    
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProviderHomeScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "الانتقال إلى لوحة المزود و إكمال الملف",
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    // ✅ حفظ نوع المستخدم كمقدم خدمة حتى لو أغلق الآن
                    final prefs = await SharedPreferences.getInstance();
                      await AccountModeService.setProviderMode(true);
                    await prefs.setBool('isProviderRegistered', true);
                    
                    setState(() => _showSuccessOverlay = false);
                  },
                  child: const Text(
                    "إغلاق الآن (سأكمل لاحقًا)",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: Colors.black54,
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFFF3F4F6),
            body: Column(
              children: [
                _buildStepHeader(),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: _buildStepContent(),
                  ),
                ),
              ],
            ),
          ),

          if (_showSuccessOverlay)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.55),
                child: _buildSuccessCard(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _SuccessHintRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SuccessHintRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: Colors.deepPurple),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'Cairo',
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
