import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/auth_guard.dart';
import '../utils/whatsapp_helper.dart';
import '../services/providers_api.dart';
import '../services/marketplace_api.dart';
import '../services/messaging_api.dart';
import '../services/session_storage.dart';
import '../services/chat_nav.dart';
import 'provider_profile_screen.dart';

class ProviderMapSelectionScreen extends StatefulWidget {
  final int subcategoryId;
  final String title;
  final String description;
  final String city;

  const ProviderMapSelectionScreen({
    super.key,
    required this.subcategoryId,
    required this.title,
    required this.description,
    required this.city,
  });

  @override
  State<ProviderMapSelectionScreen> createState() =>
      _ProviderMapSelectionScreenState();
}

class _ProviderMapSelectionScreenState
    extends State<ProviderMapSelectionScreen> {
  final MapController _mapController = MapController();
  List<dynamic> _providers = [];
  bool _loading = true;
  String? _error;
  List<int> _selectedProviderIds = [];
  bool _submitting = false;
  int? _busyProviderId;
  String? _myPhone;

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _asDisplayName(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty) return 'مزود خدمة';
    return s;
  }

  String? _asNonEmptyString(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  String _formatPhoneE164(String rawPhone) {
    final phone = rawPhone.replaceAll(RegExp(r'\s+'), '');
    if (phone.startsWith('+')) return phone;

    if (phone.startsWith('05') && phone.length == 10) {
      return '+966${phone.substring(1)}';
    }
    if (phone.startsWith('5') && phone.length == 9) {
      return '+966$phone';
    }

    return phone;
  }

  String _buildWhatsAppMessage(String providerName) {
    final buffer = StringBuffer();
    buffer.writeln('@${providerName.replaceAll(' ', '')}');
    buffer.writeln('السلام عليكم');
    buffer.writeln('أنا عميل في منصة (نوافذ)');
    buffer.writeln('أتواصل معك بخصوص طلب عاجل');
    buffer.writeln('العنوان: ${widget.title}');
    buffer.writeln('الوصف: ${widget.description}');
    buffer.writeln('المدينة: ${widget.city}');
    return buffer.toString().trim();
  }

  Future<void> _openPhoneCall(String rawPhone) async {
    final e164 = _formatPhoneE164(rawPhone);
    final uri = Uri(scheme: 'tel', path: e164);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الاتصال')),
    );
  }

  Future<void> _openWhatsApp({
    required String providerName,
    required String rawPhone,
  }) async {
    await WhatsAppHelper.open(
      context: context,
      contact: rawPhone,
      message: _buildWhatsAppMessage(providerName),
    );
  }

  Future<void> _openInAppChat({
    required String providerName,
    required String providerId,
  }) async {
    if (!await checkAuth(context)) return;
    if (!mounted) return;

    try {
      final api = MessagingApi();
      final thread = await api.getOrCreateDirectThread(int.parse(providerId));
      final threadId = thread['id'] as int?;
      if (threadId == null) throw Exception('no thread id');
      if (!mounted) return;
      ChatNav.openThread(
        context,
        threadId: threadId,
        name: providerName,
        isDirect: true,
        peerId: providerId,
        peerName: providerName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المحادثة. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _openProviderProfile(Map<String, dynamic> provider) async {
    final id = provider['id']?.toString();
    if (id == null || id.isEmpty) return;

    final name = _asDisplayName(provider['display_name']);
    final imageUrl = _asNonEmptyString(provider['image_url']);
    final phone = _asNonEmptyString(provider['phone']);
    final lat = _asDouble(provider['lat']);
    final lng = _asDouble(provider['lng']);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: id,
          providerName: name,
          providerImage: imageUrl,
          providerPhone: phone,
          providerLat: lat,
          providerLng: lng,
        ),
      ),
    );
  }

  Future<void> _sendRequestToProvider(int providerId) async {
    if (_busyProviderId != null || _submitting) return;

    setState(() => _busyProviderId = providerId);
    try {
      final marketplaceApi = MarketplaceApi();
      final success = await marketplaceApi.createRequest(
        subcategoryId: widget.subcategoryId,
        title: widget.title,
        description: widget.description,
        requestType: 'urgent',
        city: widget.city,
        providerId: providerId,
      );

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال الطلب للمزود بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل إرسال الطلب، حاول مرة أخرى'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إرسال الطلب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyProviderId = null);
      }
    }
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: (color ?? Colors.grey.shade700).withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (color ?? Colors.grey.shade700).withOpacity(0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color ?? Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color ?? Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadMyPhone();
    _loadProviders();
  }

  Future<void> _loadMyPhone() async {
    final phone = await const SessionStorage().readPhone();
    if (!mounted) return;
    setState(() => _myPhone = phone?.trim());
  }

  Future<void> _loadProviders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final providersApi = ProvidersApi();
      final providers = await providersApi.getProvidersForMap(
        subcategoryId: widget.subcategoryId,
      );
      setState(() {
        _providers = providers;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleProvider(int providerId) {
    setState(() {
      if (_selectedProviderIds.contains(providerId)) {
        _selectedProviderIds.remove(providerId);
      } else {
        _selectedProviderIds.add(providerId);
      }
    });
  }

  Future<void> _submitToSelectedProviders() async {
    if (_selectedProviderIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر مزود خدمة واحد على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final marketplaceApi = MarketplaceApi();
      
      // إرسال طلب لكل مزود مختار
      int successCount = 0;
      for (final providerId in _selectedProviderIds) {
        final success = await marketplaceApi.createRequest(
          subcategoryId: widget.subcategoryId,
          title: widget.title,
          description: widget.description,
          requestType: 'urgent',
          city: widget.city,
          providerId: providerId,
        );
        if (success) successCount++;
      }

      if (!mounted) return;

      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال الطلب لـ $successCount مزود'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل إرسال الطلبات، حاول مرة أخرى'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _submitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إرسال الطلب: $e'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // الموقع الافتراضي (الرياض)
    final defaultCenter = LatLng(24.7136, 46.6753);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.map_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'اختر من الخريطة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'اختر المزودين القريبين منك',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
        toolbarHeight: 80,
      ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadProviders,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : _providers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off,
                                size: 60,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[400]),
                            const SizedBox(height: 16),
                            const Text(
                              'لا يوجد مزودين في هذه المنطقة',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: () {
                              if (_providers.isNotEmpty) {
                                final lat = _asDouble(_providers[0]['lat']);
                                final lng = _asDouble(_providers[0]['lng']);
                                if (lat != null && lng != null) {
                                  return LatLng(lat, lng);
                                }
                              }
                              return defaultCenter;
                            }(),
                            initialZoom: 12.0,
                            minZoom: 5.0,
                            maxZoom: 18.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.nawafeth.app',
                            ),
                            MarkerLayer(
                              markers: _providers
                                  .where((p) {
                                    final lat = _asDouble(p['lat']);
                                    final lng = _asDouble(p['lng']);
                                    return lat != null && lng != null;
                                  })
                                  .map((provider) {
                                final isSelected = _selectedProviderIds
                                    .contains(provider['id']);
                                final lat = _asDouble(provider['lat'])!;
                                final lng = _asDouble(provider['lng'])!;
                                return Marker(
                                  point: LatLng(
                                    lat,
                                    lng,
                                  ),
                                  width: 50,
                                  height: 50,
                                  child: GestureDetector(
                                    onTap: () => _toggleProvider(provider['id']),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? const Color(0xFFFF6B6B)
                                            : Colors.blue,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.person_pin,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                        // قائمة المزودين في الأسفل
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 250),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[900] : Colors.white,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, -5),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Handle
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                // عدد المختارين
                                Container(
                                  margin: const EdgeInsets.all(16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B6B),
                                        Color(0xFFFF8E53)
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'المزودين المختارين: ${_selectedProviderIds.length}',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: _submitting
                                            ? null
                                            : _submitToSelectedProviders,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor:
                                              const Color(0xFFFF6B6B),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        icon: _submitting
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.send_rounded,
                                                size: 18),
                                        label: Text(
                                          _submitting ? 'جاري الإرسال...' : 'إرسال',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // قائمة المزودين
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    itemCount: _providers.length,
                                    itemBuilder: (context, index) {
                                      final provider =
                                          _providers[index] as Map<String, dynamic>;
                                      final providerId =
                                          (provider['id'] as num?)?.toInt() ?? 0;
                                      final isSelected = _selectedProviderIds
                                          .contains(providerId);
                                      final name =
                                          _asDisplayName(provider['display_name']);
                                      final city =
                                          _asNonEmptyString(provider['city']) ?? widget.city;
                                      final phone = _asNonEmptyString(provider['phone']);
                                      final whatsapp =
                                          _asNonEmptyString(provider['whatsapp']);
                                      final imageUrl =
                                          _asNonEmptyString(provider['image_url']);
                                      final canCall = phone != null;
                                      final canWhatsApp =
                                          (whatsapp ?? phone)?.trim().isNotEmpty == true ||
                                          (_myPhone?.isNotEmpty == true);
                                      final chatPhone = whatsapp ?? phone;
                                      final isBusy = _busyProviderId == providerId;

                                      final avatar = CircleAvatar(
                                        radius: 22,
                                        backgroundColor: isSelected
                                            ? const Color(0xFFFF6B6B)
                                            : Colors.blue,
                                        backgroundImage: imageUrl != null
                                            ? CachedNetworkImageProvider(imageUrl)
                                            : null,
                                        child: imageUrl == null
                                            ? Text(
                                                name.isNotEmpty
                                                    ? name.characters.first
                                                    : 'م',
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : null,
                                      );

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  GestureDetector(
                                                    onTap: () => _openProviderProfile(provider),
                                                    child: avatar,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: InkWell(
                                                      onTap: () => _openProviderProfile(provider),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            name,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              fontFamily: 'Cairo',
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            city,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              fontFamily: 'Cairo',
                                                              fontSize: 12,
                                                              color: Colors.grey,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  InkWell(
                                                    onTap: providerId > 0
                                                        ? () => _toggleProvider(providerId)
                                                        : null,
                                                    borderRadius: BorderRadius.circular(20),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? const Color(0xFFFF6B6B)
                                                            : Colors.grey[300],
                                                        borderRadius:
                                                            BorderRadius.circular(20),
                                                      ),
                                                      child: Text(
                                                        isSelected ? 'مختار' : 'اختر',
                                                        style: TextStyle(
                                                          fontFamily: 'Cairo',
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: isSelected
                                                              ? Colors.white
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  _actionChip(
                                                    icon: FontAwesomeIcons.whatsapp,
                                                    label: 'واتساب',
                                                    color: const Color(0xFF25D366),
                                                    onTap: canWhatsApp
                                                        ? () => _openWhatsApp(
                                                              providerName: name,
                                                              rawPhone: chatPhone ?? '',
                                                            )
                                                        : null,
                                                  ),
                                                  _actionChip(
                                                    icon: Icons.call,
                                                    label: 'اتصال',
                                                    color: Colors.blue,
                                                    onTap: canCall
                                                        ? () => _openPhoneCall(phone)
                                                        : null,
                                                  ),
                                                  _actionChip(
                                                    icon: Icons.chat_bubble_outline,
                                                    label: 'محادثة',
                                                    color: Colors.deepPurple,
                                                    onTap: providerId > 0
                                                        ? () => _openInAppChat(
                                                              providerName: name,
                                                              providerId: providerId.toString(),
                                                            )
                                                        : null,
                                                  ),
                                                  _actionChip(
                                                    icon: Icons.send_rounded,
                                                    label: isBusy
                                                        ? 'جارٍ الإرسال...'
                                                        : 'طلب الخدمة',
                                                    color: const Color(0xFFFF6B6B),
                                                    onTap: (providerId > 0 && !isBusy)
                                                        ? () => _sendRequestToProvider(providerId)
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
