import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:nawafeth/widgets/platform_top_bar.dart';

class MapRadiusPickerScreen extends StatefulWidget {
  final LatLng? initialCenter;
  final int radiusKm;

  const MapRadiusPickerScreen({
    super.key,
    required this.radiusKm,
    this.initialCenter,
  });

  @override
  State<MapRadiusPickerScreen> createState() => _MapRadiusPickerScreenState();
}

class _MapRadiusPickerScreenState extends State<MapRadiusPickerScreen> {
  static const Color _mainColor = Colors.deepPurple;

  late LatLng _center;
  late final MapController _mapController;
  bool _isDetectingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _center = widget.initialCenter ?? const LatLng(24.7136, 46.6753);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoCenterOnDeviceLocation();
    });
  }

  Future<void> _autoCenterOnDeviceLocation() async {
    await _centerOnCurrentLocation(showErrors: false);
  }

  Future<void> _centerOnCurrentLocation({bool showErrors = true}) async {
    if (_isDetectingLocation || !mounted) return;

    setState(() => _isDetectingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showErrors) {
          _showLocationSnackBar(
              'الرجاء تشغيل خدمة الموقع (GPS) ثم المحاولة مرة أخرى.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showErrors) {
          _showLocationSnackBar(
              'تم رفض إذن الموقع. فعّل الإذن لاستخدام موقعك الحالي.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      final current = LatLng(position.latitude, position.longitude);
      setState(() => _center = current);
      _mapController.move(current, 14);
    } catch (_) {
      if (showErrors && mounted) {
        _showLocationSnackBar('تعذر تحديد موقعك الحالي الآن.');
      }
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
      }
    }
  }

  void _showLocationSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radiusMeters = widget.radiusKm * 1000.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: const PlatformTopBar(
          pageLabel: 'تحديد الموقع',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  )
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: _mainColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'اضغط على الخريطة لاختيار موقعك. سيتم إظهار دائرة بنطاق ${widget.radiusKm} كم.',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isDetectingLocation
                      ? null
                      : () => _centerOnCurrentLocation(),
                  icon: _isDetectingLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _mainColor,
                          ),
                        )
                      : const Icon(Icons.my_location, size: 17),
                  label: Text(
                    _isDetectingLocation
                        ? 'جاري تحديد موقعك...'
                        : 'استخدام موقعي الحالي',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 12,
                      onTap: (tapPosition, point) {
                        setState(() => _center = point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.nawafeth.app',
                      ),
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _center,
                            radius: radiusMeters,
                            useRadiusInMeter: true,
                            color: _mainColor.withAlpha(35),
                            borderColor: _mainColor.withAlpha(160),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _center,
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                              child: const Icon(Icons.location_on,
                                  color: _mainColor, size: 26),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _center),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _mainColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'تأكيد',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
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
}
