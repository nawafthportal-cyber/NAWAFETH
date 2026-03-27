import 'package:flutter/material.dart';
import 'package:nawafeth/services/account_mode_service.dart';

import 'client_orders_screen.dart';
import 'provider_dashboard/provider_orders_screen.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/platform_top_bar.dart';

class OrdersHubScreen extends StatefulWidget {
  const OrdersHubScreen({super.key});

  @override
  State<OrdersHubScreen> createState() => _OrdersHubScreenState();
}

class _OrdersHubScreenState extends State<OrdersHubScreen> {
  bool _isLoading = true;
  bool _isProviderMode = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderMode = isProvider;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Colors.deepPurple),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: PlatformTopBar(
          pageLabel: _isProviderMode ? 'طلبات الخدمة' : 'طلباتي',
          showNotificationAction: false,
          showChatAction: false,
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
        body: _isProviderMode
            ? const ProviderOrdersScreen(embedded: true)
            : const ClientOrdersScreen(embedded: true),
      ),
    );
  }
}
