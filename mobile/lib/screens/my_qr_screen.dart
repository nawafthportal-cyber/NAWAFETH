import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/provider_profile_model.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/provider_share_tracking_service.dart';
import '../services/profile_service.dart';
import '../widgets/platform_top_bar.dart';
import 'login_screen.dart';

class MyQrScreen extends StatefulWidget {
  const MyQrScreen({super.key});

  @override
  State<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends State<MyQrScreen> {
  bool _isLoading = true;
  bool _isLoggedIn = true;
  String? _errorMessage;
  _QrPayload? _payload;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    setState(() {
      _isLoading = true;
      _isLoggedIn = true;
      _errorMessage = null;
    });

    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    if (!loggedIn) {
      setState(() {
        _isLoading = false;
        _isLoggedIn = false;
        _payload = null;
      });
      return;
    }

    final meResult = await ProfileService.fetchMyProfile();
    if (!meResult.isSuccess || meResult.data == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoggedIn = true;
        _errorMessage = meResult.error ?? 'تعذر تحميل بيانات الحساب';
      });
      return;
    }

    final me = meResult.data!;
    ProviderProfileModel? providerProfile;

    if (me.hasProviderProfile || me.providerProfileId != null) {
      final providerResult = await ProfileService.fetchProviderProfile();
      if (providerResult.isSuccess) {
        providerProfile = providerResult.data;
      }
    }

    if (!mounted) return;
    setState(() {
      _payload = _buildPayload(me, providerProfile);
      _isLoading = false;
    });
  }

  _QrPayload _buildPayload(
    UserProfile me,
    ProviderProfileModel? providerProfile,
  ) {
    final baseUrl = ApiClient.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final targetUrl = providerProfile != null
        ? '$baseUrl/provider/${providerProfile.id}/'
        : '$baseUrl/profile/?user=${me.id}';

    return _QrPayload(
      providerId: providerProfile?.id,
      title: providerProfile != null ? 'QR ملف مقدم الخدمة' : 'رابط نافذتي',
      subtitle: _resolveSubtitle(me, providerProfile),
      targetUrl: targetUrl,
    );
  }

  String _resolveSubtitle(
    UserProfile me,
    ProviderProfileModel? providerProfile,
  ) {
    final candidates = <String?>[
      providerProfile?.displayName,
      me.displayName,
      me.username,
    ];
    for (final candidate in candidates) {
      final text = (candidate ?? '').trim();
      if (text.isNotEmpty && !_looksLikePhone(text)) {
        return text;
      }
    }
    return 'حسابك في نوافذ';
  }

  bool _looksLikePhone(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s\-\+\(\)@]'), '');
    return RegExp(r'^0\d{8,12}$').hasMatch(normalized) ||
        RegExp(r'^9665\d{8}$').hasMatch(normalized) ||
        RegExp(r'^5\d{8}$').hasMatch(normalized);
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(redirectTo: MyQrScreen()),
      ),
    );
    if (!mounted) return;
    await _loadQr();
  }

  Future<void> _copyLink() async {
    final payload = _payload;
    if (payload == null) return;
    await Clipboard.setData(ClipboardData(text: payload.targetUrl));
    if (payload.providerId != null) {
      unawaited(
        ProviderShareTrackingService.recordProfileShare(
          providerId: payload.providerId!,
          channel: 'copy_link',
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرابط')),
    );
  }

  Future<void> _shareLink() async {
    final payload = _payload;
    if (payload == null) return;
    await SharePlus.instance.share(
      ShareParams(text: payload.targetUrl, subject: payload.title),
    );
    if (payload.providerId != null) {
      unawaited(
        ProviderShareTrackingService.recordProfileShare(
          providerId: payload.providerId!,
          channel: 'other',
        ),
      );
    }
  }

  Future<void> _openLink() async {
    final payload = _payload;
    if (payload == null) return;
    final uri = Uri.tryParse(payload.targetUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرابط غير صالح')),
      );
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: PlatformTopBar(
        pageLabel: 'QR نافذتي',
        showBackButton: Navigator.of(context).canPop(),
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const _QrLoadingState()
          : !_isLoggedIn
            ? _QrAuthGate(onLogin: _openLogin)
            : _errorMessage != null
                ? _QrErrorState(
                    message: _errorMessage!,
                    onRetry: _loadQr,
                  )
                : payload == null
                    ? _QrErrorState(
                        message: 'تعذر إنشاء بيانات QR',
                        onRetry: _loadQr,
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth <= 360;
                                final qrSize = narrow ? constraints.maxWidth * 0.74 : 240.0;

                                Widget actionButton({
                                  required VoidCallback onPressed,
                                  required IconData icon,
                                  required String label,
                                }) {
                                  return OutlinedButton.icon(
                                    onPressed: onPressed,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: Size(narrow ? double.infinity : 0, 38),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 0,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(
                                        color: const Color(0xFF2F2853).withValues(alpha: 0.12),
                                      ),
                                      foregroundColor: const Color(0xFF2F2853),
                                    ),
                                    icon: Icon(icon, size: 18),
                                    label: Text(
                                      label,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  );
                                }

                                return Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.fromLTRB(
                                    narrow ? 14 : 20,
                                    narrow ? 16 : 20,
                                    narrow ? 14 : 20,
                                    narrow ? 16 : 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(narrow ? 20 : 24),
                                    border: Border.all(
                                      color: const Color(0xFF1A1A2E).withValues(alpha: 0.10),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x14161229),
                                        blurRadius: 30,
                                        offset: Offset(0, 14),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        payload.title,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF2F2853),
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        payload.subtitle,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          color: Color(0xFF6A6488),
                                          fontWeight: FontWeight.w700,
                                          height: 1.7,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        width: qrSize,
                                        height: qrSize,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(22),
                                          border: Border.all(
                                            color: const Color(0xFF1A1A2E).withValues(alpha: 0.09),
                                          ),
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl: payload.qrImageUrl,
                                          fit: BoxFit.contain,
                                          errorWidget: (_, __, ___) {
                                            return const Center(
                                              child: Text(
                                                'تعذر تحميل صورة QR',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF726A95),
                                                  height: 1.6,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SelectableText(
                                        payload.targetUrl,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          color: Color(0xFF2F2853),
                                          fontWeight: FontWeight.w700,
                                          height: 1.6,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 18),
                                      if (narrow)
                                        Column(
                                          children: [
                                            actionButton(
                                              onPressed: _copyLink,
                                              icon: Icons.copy,
                                              label: 'نسخ الرابط',
                                            ),
                                            const SizedBox(height: 10),
                                            actionButton(
                                              onPressed: _shareLink,
                                              icon: Icons.share,
                                              label: 'مشاركة',
                                            ),
                                            const SizedBox(height: 10),
                                            actionButton(
                                              onPressed: _openLink,
                                              icon: Icons.open_in_new,
                                              label: 'فتح الرابط',
                                            ),
                                          ],
                                        )
                                      else
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            actionButton(
                                              onPressed: _copyLink,
                                              icon: Icons.copy,
                                              label: 'نسخ الرابط',
                                            ),
                                            actionButton(
                                              onPressed: _shareLink,
                                              icon: Icons.share,
                                              label: 'مشاركة',
                                            ),
                                            actionButton(
                                              onPressed: _openLink,
                                              icon: Icons.open_in_new,
                                              label: 'فتح الرابط',
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
      ),
    );
  }
}

class _QrPayload {
  final int? providerId;
  final String title;
  final String subtitle;
  final String targetUrl;

  const _QrPayload({
    this.providerId,
    required this.title,
    required this.subtitle,
    required this.targetUrl,
  });

  String get qrImageUrl =>
      'https://api.qrserver.com/v1/create-qr-code/?size=420x420&data=${Uri.encodeComponent(targetUrl)}';
}

class _QrErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _QrErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, minHeight: 280),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF673AB7).withValues(alpha: 0.16)),
                  color: const Color(0xFF673AB7).withValues(alpha: 0.08),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 28,
                  color: Color(0xFF5B4D87),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5E577A),
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  onRetry();
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrLoadingState extends StatelessWidget {
  const _QrLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, minHeight: 280),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}

class _QrAuthGate extends StatelessWidget {
  final Future<void> Function() onLogin;

  const _QrAuthGate({
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF5F3FF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE9D5FF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x147C4FD4),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0x147C4FD4),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Color(0xFF7C4FD4),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'سجّل دخولك',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF5B21B6),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'لعرض كود نافذتي، سجّل دخولك أولاً',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4FD4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
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
}
