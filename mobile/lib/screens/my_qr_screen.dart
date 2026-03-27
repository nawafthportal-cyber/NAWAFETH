import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/provider_profile_model.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';
import '../widgets/platform_top_bar.dart';

class MyQrScreen extends StatefulWidget {
  const MyQrScreen({super.key});

  @override
  State<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends State<MyQrScreen> {
  bool _isLoading = true;
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
      _errorMessage = null;
    });

    final meResult = await ProfileService.fetchMyProfile();
    if (!meResult.isSuccess || meResult.data == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
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
      title: providerProfile != null ? 'QR ملف مقدم الخدمة' : 'رابط نافذتي',
      subtitle: providerProfile?.displayName.isNotEmpty == true
          ? providerProfile!.displayName
          : me.displayName,
      targetUrl: targetUrl,
    );
  }

  Future<void> _copyLink() async {
    final payload = _payload;
    if (payload == null) return;
    await Clipboard.setData(ClipboardData(text: payload.targetUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرابط')),
    );
  }

  Future<void> _shareLink() async {
    final payload = _payload;
    if (payload == null) return;
    await Share.share(payload.targetUrl, subject: payload.title);
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
            ? const Center(child: CircularProgressIndicator())
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
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Card(
                              color: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Text(
                                      payload.title,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      payload.subtitle,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      width: 240,
                                      height: 240,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                        ),
                                      ),
                                      child: Image.network(
                                        payload.qrImageUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) {
                                          return const Center(
                                            child: Text(
                                              'تعذر تحميل صورة QR',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
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
                                        color: Colors.black87,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 18),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _copyLink,
                                          icon:
                                              const Icon(Icons.copy, size: 18),
                                          label: const Text(
                                            'نسخ الرابط',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _shareLink,
                                          icon:
                                              const Icon(Icons.share, size: 18),
                                          label: const Text(
                                            'مشاركة',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _openLink,
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'فتح الرابط',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
      ),
    );
  }
}

class _QrPayload {
  final String title;
  final String subtitle;
  final String targetUrl;

  const _QrPayload({
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_rounded, size: 54, color: Colors.black54),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                onRetry();
              },
              child: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
