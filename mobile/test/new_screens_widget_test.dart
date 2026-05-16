import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nawafeth/constants/app_theme.dart';
import 'package:nawafeth/models/category_model.dart';
import 'package:nawafeth/models/featured_specialist_model.dart';
import 'package:nawafeth/screens/home_screen.dart';
import 'package:nawafeth/screens/login_screen.dart';
import 'package:nawafeth/screens/onboarding_screen.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/content_service.dart';
import 'package:nawafeth/services/home_service.dart';
import 'package:nawafeth/services/local_cache_service.dart';
import 'package:nawafeth/services/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DeviceCase {
  final String name;
  final Size size;

  const _DeviceCase(this.name, this.size);
}

const _deviceCases = <_DeviceCase>[
  _DeviceCase('small', Size(320, 640)),
  _DeviceCase('medium', Size(390, 844)),
  _DeviceCase('large', Size(430, 932)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  setUp(() async {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = (call.arguments as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final key = arguments['key']?.toString();
      switch (call.method) {
        case 'read':
          return key == null ? null : secureStore[key];
        case 'write':
          if (key != null) {
            secureStore[key] = arguments['value']?.toString() ?? '';
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStore.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
        default:
          return null;
      }
    });
    SharedPreferences.setMockInitialValues({});
    LocalCacheService.debugReset();
    await LocalCacheService.init();
    await ContentService.clearCache();
    await HomeService.debugResetCaches();
    ApiClient.debugResetHttpClient();
  });

  tearDown(() {
    ApiClient.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  for (final device in _deviceCases) {
    testWidgets(
      'onboarding renders on ${device.name} viewport',
      (tester) async {
        await _pumpScreen(
          tester,
          device.size,
          const OnboardingScreen(),
          routes: {
            '/login': (_) => const _RouteStub(label: 'LOGIN_SCREEN'),
            '/home': (_) => const _RouteStub(label: 'HOME_SCREEN'),
          },
        );

        expect(find.text('كل خدماتك في مكان واحد'), findsOneWidget);
        expect(find.text('التالي'), findsOneWidget);
        expect(find.text('تخطي'), findsWidgets);
        _expectNoPendingFlutterExceptions(tester);
      },
    );

    testWidgets(
      'login renders on ${device.name} viewport',
      (tester) async {
        ApiClient.debugSetHttpClient(
          MockClient((request) async {
            return http.Response(
              jsonEncode({'blocks': <String, dynamic>{}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        await _pumpScreen(tester, device.size, const LoginScreen());

        expect(find.text('مرحبًا بعودتك'), findsOneWidget);
        expect(find.text('رقم الجوال'), findsWidgets);
        expect(find.widgetWithText(ElevatedButton, 'تسجيل الدخول'),
            findsOneWidget);
        _expectNoPendingFlutterExceptions(tester);
      },
    );

    testWidgets(
      'home renders web-aligned sections on ${device.name} viewport',
      (tester) async {
        await _pumpScreen(
          tester,
          device.size,
          HomeScreen(debugState: _homeDebugState),
        );

        expect(find.text('نوافذ'), findsWidgets);
        expect(find.text('تمت مزامنة الشاشة الرئيسية محليًا للاختبار.'),
            findsWidgets);
        expect(find.text('التصنيفات'), findsOneWidget);
        expect(find.text('قانون'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('أبرز المختصين'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('أبرز المختصين'), findsOneWidget);
        expect(find.text('مختص أول'), findsOneWidget);
        _expectNoPendingFlutterExceptions(tester);
      },
    );
  }

  testWidgets('onboarding completion routes to login and stores seen flag',
      (tester) async {
    await _pumpScreen(
      tester,
      _deviceCases[1].size,
      const OnboardingScreen(),
      routes: {
        '/login': (_) => const _RouteStub(label: 'LOGIN_SCREEN'),
        '/home': (_) => const _RouteStub(label: 'HOME_SCREEN'),
      },
    );

    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.text('ابدأ رحلتك الآن'), findsOneWidget);

    await tester.tap(find.text('ابدأ الآن'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_SCREEN'), findsOneWidget);
    expect(await OnboardingService.shouldShowOnboarding(), isFalse);
    _expectNoPendingFlutterExceptions(tester);
  });

  testWidgets('login prevents duplicate OTP submission while loading',
      (tester) async {
    var otpRequestCount = 0;
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/accounts/otp/send/') {
          otpRequestCount += 1;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          return http.Response(
            jsonEncode({'cooldown_seconds': 60}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'blocks': <String, dynamic>{}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await _pumpScreen(tester, _deviceCases[1].size, const LoginScreen());

    await tester.enterText(find.byType(TextField).first, '0555555555');
    await tester.pump();

    final submitButton = find.widgetWithText(ElevatedButton, 'تسجيل الدخول');
    await tester.tap(submitButton);
    await tester.pump(const Duration(milliseconds: 20));

    expect(otpRequestCount, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(milliseconds: 20));

    expect(otpRequestCount, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(otpRequestCount, 1);
    _expectNoPendingFlutterExceptions(tester);
  });
}

final _homeDebugState = HomeScreenDebugState(
  content: HomeScreenContent(
    categoriesTitle: 'التصنيفات',
    providersTitle: 'أبرز المختصين',
    bannersTitle: 'العروض',
    fallbackBanner: null,
  ),
  categories: [
    CategoryModel(id: 1, name: 'قانون'),
    CategoryModel(id: 2, name: 'تقنية'),
    CategoryModel(id: 3, name: 'تسويق'),
  ],
  featuredSpecialists: [
    FeaturedSpecialistModel(
      placementId: 1,
      providerId: 101,
      displayName: 'مختص أول',
    ),
    FeaturedSpecialistModel(
      placementId: 2,
      providerId: 102,
      displayName: 'مختص ثان',
    ),
  ],
  isLoggedIn: true,
  notificationUnread: 3,
  showOverviewOnly: true,
  accountDisplayName: 'محمد',
  accountSubtitle: 'راجع التنبيهات، الطلبات، وأحدث النشاط من واجهة واحدة.',
  syncMessage: 'تمت مزامنة الشاشة الرئيسية محليًا للاختبار.',
);

Future<void> _pumpScreen(
  WidgetTester tester,
  Size size,
  Widget child, {
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
      routes: routes,
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoPendingFlutterExceptions(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull, reason: exception?.toString());
}

class _RouteStub extends StatelessWidget {
  final String label;

  const _RouteStub({required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(label),
      ),
    );
  }
}
