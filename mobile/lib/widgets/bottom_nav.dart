import 'package:flutter/material.dart';
import '../services/account_mode_service.dart';
import '../constants/colors.dart';

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
        height: 118 + bottomInset,
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
                  height: 82 + bottomInset,
                  padding: EdgeInsets.only(bottom: bottomInset),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.08 * 255).toInt()),
                        blurRadius: 20,
                        spreadRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
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
                bottom: 24 + (bottomInset * 0.2),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onAddServicePressed(context),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0x40DA52FF), // ✅ بديل withOpacity(0.25)
                              Colors.transparent,
                            ],
                            radius: 0.6,
                          ),
                        ),
                      ),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            const BoxShadow(
                              color: Color(0x4DFF0000), // ✅ بديل withOpacity(0.3)
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, size: 24, color: Colors.white),
                            SizedBox(height: 2),
                            Text(
                              "خدمة",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
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
    final Color activeColor = AppColors.accentOrange;
    final Color defaultColor = isDark ? Colors.white70 : AppColors.deepPurple;

    final Color contentColor = selected ? activeColor : defaultColor;

    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? activeColor.withAlpha(28) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: contentColor, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
