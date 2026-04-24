import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'constants/app_theme.dart';
import 'services/auth_service.dart';
import 'services/onboarding_service.dart';
import 'services/account_mode_service.dart';
import 'services/local_cache_service.dart';
import 'services/push_notification_service.dart';
import 'services/payment_return_service.dart';

// 🟣 الشاشات الرئيسية
import 'screens/home_screen.dart';
import 'screens/my_chats_screen.dart';
import 'screens/interactive_screen.dart';
import 'screens/my_profile_screen.dart';
import 'screens/add_service_screen.dart';

// 🟢 الشاشات الجديدة
import 'screens/login_screen.dart';
import 'screens/search_provider_screen.dart';
import 'screens/urgent_request_screen.dart';
import 'screens/request_quote_screen.dart';
import 'screens/orders_hub_screen.dart';

// 🆕 شاشة الترحيب (Onboarding)
import 'screens/onboarding_screen.dart';

/// 🌙 وحدة تحكم للثيم واللغة
class MyThemeController extends InheritedWidget {
  final void Function(ThemeMode) changeTheme;
  final void Function(Locale) changeLanguage;
  final ThemeMode themeMode;
  final Locale locale;

  const MyThemeController({
    super.key,
    required this.changeTheme,
    required this.themeMode,
    required this.changeLanguage,
    required this.locale,
    required super.child,
  });

  static MyThemeController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MyThemeController>();

  @override
  bool updateShouldNotify(MyThemeController oldWidget) =>
      oldWidget.themeMode != themeMode || oldWidget.locale != locale;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalCacheService.init();
  await PushNotificationService.initialize();
  await PaymentReturnService.initialize();
  final showOnboarding = await OnboardingService.shouldShowOnboarding();
  final isLoggedIn = await AuthService.isLoggedIn();
  runApp(NawafethApp(showOnboarding: showOnboarding, isLoggedIn: isLoggedIn));
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class NawafethApp extends StatefulWidget {
  final bool showOnboarding;
  final bool isLoggedIn;

  const NawafethApp({
    super.key,
    required this.showOnboarding,
    required this.isLoggedIn,
  });

  @override
  State<NawafethApp> createState() => _NawafethAppState();
}

class _NawafethAppState extends State<NawafethApp> {
  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = const Locale('ar', 'SA'); // ✅ اللغة الافتراضية العربية
  StreamSubscription<PaymentReturnPayload>? _paymentReturnSubscription;

  @override
  void initState() {
    super.initState();
    _paymentReturnSubscription = PaymentReturnService.stream.listen((payload) {
      final state = rootNavigatorKey.currentState;
      if (state == null || !state.mounted) return;
      PaymentReturnService.showSnackBar(state.context, payload);
    });
  }

  @override
  void dispose() {
    _paymentReturnSubscription?.cancel();
    super.dispose();
  }

  /// 🔄 تبديل الثيم
  void _changeTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  /// 🔄 تبديل اللغة
  void _changeLanguage(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MyThemeController(
      changeTheme: _changeTheme,
      themeMode: _themeMode,
      changeLanguage: _changeLanguage,
      locale: _locale,
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'Nawafeth App',
        debugShowCheckedModeBanner: false,

        // ✅ إعدادات الثيم
        themeMode: _themeMode,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,

        // ✅ دعم تعدد اللغات
        locale: _locale,
        supportedLocales: const [Locale('ar', 'SA'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        // ✅ المسارات
        initialRoute: widget.showOnboarding ? '/onboarding' : '/home',
        routes: {
          '/onboarding': (context) => const OnboardingScreen(),
          '/home': (context) => const HomeScreen(),
          '/chats': (context) => const MyChatsScreen(),
          '/orders': (context) => const OrdersHubScreen(),
          '/interactive': (context) => const InteractiveScreen(),
          '/profile': (context) => const MyProfileScreen(),
          '/add_service': (context) => const AddServiceScreen(),

          // ✅ الشاشات الجديدة
          '/login': (context) => const LoginScreen(),
          '/search_provider': (context) => const _ModeRouteGuard(
                allowProviderMode: false,
                redirectRoute: '/profile',
                child: SearchProviderScreen(),
              ),
          '/urgent_request': (context) => const _ModeRouteGuard(
                allowProviderMode: false,
                redirectRoute: '/profile',
                child: UrgentRequestScreen(),
              ),
          '/request_quote': (context) => const _ModeRouteGuard(
                allowProviderMode: false,
                redirectRoute: '/profile',
                child: RequestQuoteScreen(),
              ),
        },
      ),
    );
  }
}

class _ModeRouteGuard extends StatefulWidget {
  final bool allowProviderMode;
  final String redirectRoute;
  final Widget child;

  const _ModeRouteGuard({
    required this.allowProviderMode,
    required this.redirectRoute,
    required this.child,
  });

  @override
  State<_ModeRouteGuard> createState() => _ModeRouteGuardState();
}

class _ModeRouteGuardState extends State<_ModeRouteGuard> {
  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;

    final allowed = widget.allowProviderMode ? isProvider : !isProvider;
    if (!allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, widget.redirectRoute);
      });
    }

    setState(() {
      _allowed = allowed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    if (!_allowed) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    return widget.child;
  }
}
