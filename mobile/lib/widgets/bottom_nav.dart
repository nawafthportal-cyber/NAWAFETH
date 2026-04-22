import 'package:flutter/material.dart';
import '../services/account_mode_service.dart';
import '../constants/app_theme.dart';

class CustomBottomNav extends StatefulWidget {
  final int currentIndex;

  const CustomBottomNav({required this.currentIndex, super.key});

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav> {
  bool _isProviderMode = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() => _isProviderMode = isProvider);
  }

  void _navigate(BuildContext context, int index) {
    if (widget.currentIndex >= 0 && index == widget.currentIndex) return;

    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/orders');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/interactive');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  void _onAddServicePressed(BuildContext context) {
    Navigator.pushNamed(context, '/add_service');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 96 + bottomInset,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // ✅ الشريط السفلي بخلفية منحنية ومرتبة
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipPath(
                clipper: CurvedNotchClipper(),
                child: Container(
                  height: 62 + bottomInset,
                  padding: EdgeInsets.only(bottom: bottomInset),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : AppColors.surfaceLight,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight,
                        width: 0.6,
                      ),
                    ),
                    boxShadow: AppShadows.topBar,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // ✅ الرئيسية (أقصى اليمين)
                      IconWithLabel(
                        icon: Icons.home,
                        label: "الرئيسية",
                        selected: widget.currentIndex == 0,
                        onTap: () => _navigate(context, 0),
                      ),

                      // ✅ طلباتي
                      if (!_isProviderMode)
                        IconWithLabel(
                          icon: Icons.list_alt,
                          label: "طلباتي",
                          selected: widget.currentIndex == 1,
                          onTap: () => _navigate(context, 1),
                        )
                      else
                        const SizedBox(width: 52),

                      // ✅ زر الخدمة في المنتصف
                      const SizedBox(width: 40),

                      // ✅ تفاعلي
                      IconWithLabel(
                        icon: Icons.group,
                        label: "تفاعلي",
                        selected: widget.currentIndex == 2,
                        onTap: () => _navigate(context, 2),
                      ),

                      // ✅ نافذتي (أقصى اليسار)
                      IconWithLabel(
                        icon: Icons.person,
                        label: "نافذتي",
                        selected: widget.currentIndex == 3,
                        onTap: () => _navigate(context, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ✅ زر "خدمة" العائم في المنتصف - يظهر فقط في الصفحة الرئيسية
            if (widget.currentIndex == 0)
              Positioned(
                bottom: 18 + (bottomInset * 0.2),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onAddServicePressed(context),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Subtle glow ring
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0x2860269E), Colors.transparent],
                            radius: 0.7,
                          ),
                        ),
                      ),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.primaryLight, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x4060269E),
                              blurRadius: 14,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, size: 20, color: Colors.white),
                            SizedBox(height: 1),
                            Text(
                              "خدمة",
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class IconWithLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const IconWithLabel({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color activeColor = AppColors.primary;
    final Color defaultColor = isDark ? const Color(0xFF8892A4) : const Color(0xFF8892A4);

    final Color contentColor = selected ? activeColor : defaultColor;

    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? activeColor.withAlpha(18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: contentColor, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.micro,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: contentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurvedNotchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const notchRadius = 38.0;
    final center = size.width / 2;

    path.lineTo(center - notchRadius * 1.8, 0);
    path.quadraticBezierTo(
      center - notchRadius,
      0,
      center - notchRadius * 0.95,
      notchRadius * 0.6,
    );
    path.arcToPoint(
      Offset(center + notchRadius * 0.95, notchRadius * 0.6),
      radius: const Radius.circular(notchRadius),
      clockwise: false,
    );
    path.quadraticBezierTo(
      center + notchRadius,
      0,
      center + notchRadius * 1.8,
      0,
    );
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
