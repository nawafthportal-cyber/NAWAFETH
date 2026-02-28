import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:nawafeth/widgets/app_bar.dart';
import 'package:nawafeth/widgets/bottom_nav.dart';
import 'package:nawafeth/widgets/custom_drawer.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/models/user_profile.dart';
import 'package:nawafeth/models/provider_profile_model.dart';

import 'profile_tab.dart';
import 'services_tab.dart';
import 'reviews_tab.dart';
import 'package:nawafeth/screens/provider_dashboard/provider_orders_screen.dart';
import 'package:nawafeth/screens/verification_screen.dart';
import 'package:nawafeth/screens/plans_screen.dart';
import 'package:nawafeth/screens/additional_services_screen.dart';
import 'package:nawafeth/screens/registration/steps/content_step.dart';
import 'package:nawafeth/screens/provider_dashboard/promotion_screen.dart';

// ✅ شاشة إكمال الملف التعريفي (تكون موجودة عندك وتستدعي فيها القوالب)
import 'package:nawafeth/screens/provider_dashboard/provider_profile_completion_screen.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen>
    with SingleTickerProviderStateMixin {
  final Color mainColor = Colors.deepPurple;

  File? _profileImage;
  File? _coverImage;
  File? _reelVideo;

  late AnimationController _controller;

  // ────── حالات التحميل ──────
  bool _isLoading = true;
  String? _errorMessage;

  // ────── بيانات من الـ API ──────
  UserProfile? _userProfile;
  ProviderProfileModel? _providerProfile;

  // ────── بيانات محسوبة ──────
  String get _currentPlanName => "الباقة المجانية"; // TODO: ربط بـ subscriptions API
  int get _followersCount => _userProfile?.providerFollowersCount ?? 0;
  int get _followingCount => _userProfile?.followingCount ?? 0;
  int get _likesReceivedCount => _userProfile?.providerLikesReceivedCount ?? 0;
  int get _favoritesCount => _userProfile?.favoritesMediaCount ?? 0;
  String get _displayName => _providerProfile?.displayName ?? _userProfile?.providerDisplayName ?? '';

  // ✅ نسبة إكمال الملف من البيانات الحقيقية
  double get _profileCompletion => _providerProfile?.profileCompletion ?? 0.30;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _loadProviderData();
  }

  /// ✅ تحميل بيانات المزود من الـ API
  Future<void> _loadProviderData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // جلب بيانات المستخدم الأساسية
    final meResult = await ProfileService.fetchMyProfile();
    if (!mounted) return;

    if (!meResult.isSuccess || meResult.data == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = meResult.error ?? 'خطأ في جلب البيانات';
      });
      return;
    }

    _userProfile = meResult.data;

    // جلب بيانات ملف المزود
    final providerResult = await ProfileService.fetchProviderProfile();
    if (!mounted) return;

    if (providerResult.isSuccess && providerResult.data != null) {
      _providerProfile = providerResult.data;
    }
    // نستمر حتى لو فشل جلب ملف المزود — نعرض البيانات المتاحة

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // اختيار صورة الغلاف / الصورة الشخصية
  Future<void> _pickImage({required bool isCover}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (isCover) {
          _coverImage = File(picked.path);
        } else {
          _profileImage = File(picked.path);
        }
      });
    }
  }

  // اختيار فيديو ريلز
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _reelVideo = File(picked.path);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم اختيار فيديو ريلز بنجاح")),
      );
    }
  }

  // نافذة QR
  void _showQrDialog() {
    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "رمز QR الخاص بك",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "QR CODE",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(text: "QR-CODE-DATA"),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("تم نسخ الكود")),
                            );
                          },
                          icon: const Icon(
                            Icons.copy,
                            color: Colors.deepPurple,
                          ),
                          tooltip: "نسخ",
                        ),
                        IconButton(
                          onPressed: () {
                            Share.share("QR-CODE-DATA");
                          },
                          icon: const Icon(
                            Icons.share,
                            color: Colors.deepPurple,
                          ),
                          tooltip: "مشاركة",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          "إغلاق",
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            color: Colors.white,
                          ),
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

  // عنصر إحصائية بسيط
  Widget _statItem({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: mainColor),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 11,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // أزرار التنقل الثلاثة
  Widget _dashboardButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black12.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: mainColor),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: "Cairo",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // كرت الباقة (ذهبي بسيط)
  Widget _planCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Color(0xFFF9A825)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _currentPlanName,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlansScreen()),
              );
            },
            child: const Text(
              "ترقية",
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 12,
                color: Color(0xFFF57F17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ كرت اكتمال الملف — كامل الكرت ينقل إلى شاشة إكمال الملف التعريفي
  Widget _profileCompletionCard() {
    final percent = (_profileCompletion * 100).round();
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ProviderProfileCompletionScreen(),
          ),
        );
        if (!mounted) return;
        await _loadProviderData();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F4FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "اكتمال الملف",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  "$percent%",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: mainColor,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: mainColor.withOpacity(0.8),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: LinearProgressIndicator(
                value: _profileCompletion,
                minHeight: 6,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(mainColor),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "اضغط هنا لإكمال بقية بيانات ملفك التعريفي.",
              style: TextStyle(
                fontSize: 11,
                color: Colors.black54,
                fontFamily: "Cairo",
              ),
            ),
          ],
        ),
      ),
    );
  }

  // رأس الصفحة: غلاف + صورة شخصية + اسم
  Widget _buildHeader() {
    // ✅ تحديد مصدر صورة الغلاف (محلية أولاً، ثم من API)
    final coverUrl = ApiClient.buildMediaUrl(_providerProfile?.coverImage);
    ImageProvider? coverImageProvider;
    if (_coverImage != null) {
      coverImageProvider = FileImage(_coverImage!);
    } else if (coverUrl != null) {
      coverImageProvider = NetworkImage(coverUrl);
    }

    // ✅ تحديد مصدر الصورة الشخصية (محلية أولاً، ثم من API)
    final profileUrl = ApiClient.buildMediaUrl(_providerProfile?.profileImage);
    ImageProvider? profileImageProvider;
    if (_profileImage != null) {
      profileImageProvider = FileImage(_profileImage!);
    } else if (profileUrl != null) {
      profileImageProvider = NetworkImage(profileUrl);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _pickImage(isCover: true),
          child: Container(
            height: 190,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient:
                  coverImageProvider == null
                      ? LinearGradient(
                        colors: [
                          mainColor,
                          mainColor.withOpacity(0.6),
                        ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      )
                      : null,
              image:
                  coverImageProvider != null
                      ? DecorationImage(
                        image: coverImageProvider,
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
          ),
        ),
        // زر الكاميرا وزر التبديل
        Positioned(
          top: 8,
          left: 16,
          child: SafeArea(
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => _pickImage(isCover: true),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 16,
          child: SafeArea(
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await AccountModeService.setProviderMode(false);
                    
                    if (mounted) {
                      // إظهار إشعار التبديل
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'تم التبديل إلى حساب العميل بنجاح',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 5),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                      
                      Navigator.pushReplacementNamed(context, '/profile');
                    }
                  },
                  borderRadius: BorderRadius.circular(25),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.person,
                          size: 18,
                          color: Colors.deepPurple,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'حساب عميل',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // صورة شخصية
        Positioned(
          bottom: -40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _pickImage(isCover: false),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: profileImageProvider,
                      child:
                          profileImageProvider == null
                              ? const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 38,
                              )
                              : null,
                    ),
                  ),
                  Positioned(
                    bottom: 3,
                    right: 3,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: mainColor,
                      child: const Icon(
                        Icons.edit,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // إدارة الطلبات
  Widget _ordersCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProviderOrdersScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black12.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor.withOpacity(0.1),
                ),
                child: Icon(Icons.list_alt, color: mainColor),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "إدارة الطلبات",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: "Cairo",
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "2 عاجلة",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: "Cairo",
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Text(
                  "5 جديدة",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: "Cairo",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ريلز
  Widget _reelsRow() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return GestureDetector(
              onTap: _pickVideo,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: mainColor, width: 2),
                  color: Colors.white,
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white,
                  child: Icon(
                    _reelVideo == null ? Icons.add : Icons.edit,
                    color: mainColor,
                    size: 26,
                  ),
                ),
              ),
            );
          } else {
            return RotationTransition(
              turns: _controller,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFE1BEE7), Color(0xFFFFB74D)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: const CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.deepPurple,
                    size: 26,
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // زر خدمة إضافية (pill)
  Widget _servicePill(
    IconData icon,
    String label,
    Color color, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: "Cairo",
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // الخدمات الإضافية
  Widget _extraServicesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              "خدمات إضافية لتعزيز ظهورك:",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                fontFamily: "Cairo",
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _servicePill(
                  Icons.campaign,
                  "ترويج",
                  Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PromotionScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _servicePill(
                  Icons.monetization_on,
                  "ترقية",
                  Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlansScreen()),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _servicePill(
                  Icons.verified,
                  "توثيق",
                  Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VerificationScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdditionalServicesScreen(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "عرض كل الخدمات الإضافية",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: "Cairo",
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ شاشة خطأ
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProviderData,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        drawer: const CustomDrawer(),
        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: CustomAppBar(showSearchField: false, title: 'نافذتي'),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
            : _errorMessage != null
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: _loadProviderData,
                    color: mainColor,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 52),
              // بطاقة رئيسية تحت الغلاف
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // الإحصائيات + الباقة + اكتمال الملف
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // ✅ إحصائيات المتابعين والمتابعون — من الـ API
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('قائمة المتابعين'),
                                    ),
                                  );
                                },
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.groups_rounded,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$_followersCount',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'متابع',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 40),
                              GestureDetector(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('قائمة المتابَعون'),
                                    ),
                                  );
                                },
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$_followingCount',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'يتابع',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _statItem(
                                icon: Icons.thumb_up_alt_outlined,
                                label: "إعجابات",
                                value: '$_likesReceivedCount',
                              ),
                              const SizedBox(width: 6),
                              _statItem(
                                icon: Icons.person_outline,
                                label: "عملاء",
                                value: "0", // TODO: ربط بـ endpoint عدد العملاء
                              ),
                              const SizedBox(width: 6),
                              _statItem(
                                icon: Icons.bookmark_border,
                                label: "محفوظ",
                                value: '$_favoritesCount',
                              ),
                              const SizedBox(width: 6),
                              _statItem(
                                icon: Icons.qr_code,
                                label: "QR",
                                value: "",
                                onTap: _showQrDialog,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _planCard(),
                          const SizedBox(height: 10),
                          _profileCompletionCard(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ordersCard(),
                  ],
                ),
              ),
              _reelsRow(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _dashboardButton(Icons.person, "الملف الشخصي", () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileTab(),
                            ),
                          );
                        }),
                        _dashboardButton(
                          Icons.home_repair_service,
                          "خدماتي",
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ServicesTab(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _dashboardButton(Icons.reviews, "المراجعات", () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ReviewsTab(),
                            ),
                          );
                        }),
                        _dashboardButton(
                          Icons.photo_library_outlined,
                          "معرض الأعمال",
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => ContentStep(
                                      onBack: () => Navigator.pop(context),
                                      onNext: () => Navigator.pop(context),
                                    ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _extraServicesSection(),
              const SizedBox(height: 60),
            ],
          ),
        ),
                  ),
      ),
    );
  }
}
