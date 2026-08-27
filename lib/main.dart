import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/payment_test_result.dart';
import 'screens/payment/payment_result_screen.dart';
import 'services/payment_deep_link_service.dart';
import 'utils/constants.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/profile/notifications_screen.dart';
import 'screens/auth/registration_flow/registration_checklist_screen.dart';
import 'services/notification_service.dart';
import 'services/quote_service.dart';
import 'services/cart_service.dart';
import 'services/registration_gate_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

const SystemUiOverlayStyle _systemNavigationBarStyle = SystemUiOverlayStyle(
  systemNavigationBarColor: Colors.white,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(_systemNavigationBarStyle);
  await Constants.init();

  try {
    await QuoteService.init();
  } catch (e) {
    debugPrint('Error inicializando QuoteService: $e');
  }

  try {
    if (Constants.hasSupabaseConfig) {
      await Supabase.initialize(
        url: Constants.supabaseUrl,
        publishableKey: Constants.supabaseAnonKey,
      );
    }
  } catch (e) {
    debugPrint('Error inicializando Supabase: $e');
  }

  runApp(const GoMedicalApp());
}

class GoMedicalApp extends StatefulWidget {
  const GoMedicalApp({super.key});

  @override
  State<GoMedicalApp> createState() => _GoMedicalAppState();
}

class _GoMedicalAppState extends State<GoMedicalApp> {
  final PaymentDeepLinkService _paymentDeepLinkService =
      PaymentDeepLinkService();
  bool _isNavigatingPaymentResult = false;
  bool _isOpeningNotification = false;
  StreamSubscription<String?>? _notificationTapSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotifications();
    });
  }

  Future<void> _initDeepLinks() async {
    await _paymentDeepLinkService.init(onResult: _showPaymentResult);
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService.instance.init();
      if (!mounted) return;
      _initNotificationTaps();
    } catch (e) {
      debugPrint('Error inicializando NotificationService: $e');
    }
  }

  void _showPaymentResult(PaymentTestResult result) {
    if (_isNavigatingPaymentResult) return;

    if (result == PaymentTestResult.success ||
        result == PaymentTestResult.pending) {
      CartService.clearLocalCartCache();
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPaymentResult(result);
      });
      return;
    }

    _isNavigatingPaymentResult = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PaymentResultScreen(result: result),
          ),
        )
        .whenComplete(() {
          _isNavigatingPaymentResult = false;
        });
  }

  void _initNotificationTaps() {
    if (_notificationTapSubscription != null) return;
    _notificationTapSubscription = NotificationService
        .instance
        .notificationTapStream
        .listen(_openNotification);
    final pending = NotificationService.instance.takePendingTapPayload();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotification(pending);
      });
    }
  }

  void _openNotification(String? notificationId) {
    if (_isOpeningNotification) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotification(notificationId);
      });
      return;
    }
    _isOpeningNotification = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NotificationsListScreen(initialNotificationId: notificationId),
          ),
        )
        .whenComplete(() {
          _isOpeningNotification = false;
        });
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _paymentDeepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      navigatorKey: appNavigatorKey,
      title: 'Go Medical',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _systemNavigationBarStyle,
          child: ColoredBox(
            color: Colors.white,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF0D9488),
          onPrimary: Colors.white,
          secondary: Color(0xFF0F172A),
          onSecondary: Colors.white,
          tertiary: Color(0xFF10B981),
          onTertiary: Colors.white,
          error: Color(0xFFF43F5E),
          onError: Colors.white,
          surface: Color(0xFFF8FAFC),
          onSurface: Color(0xFF0F172A),
        ),
        appBarTheme: const AppBarTheme(
          titleSpacing: 4,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF0F172A),
          ),
          displayMedium: TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF0F172A),
          ),
          displaySmall: TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF0F172A),
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          titleSmall: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          bodyLarge: TextStyle(fontFamily: 'Inter', color: Color(0xFF1E293B)),
          bodyMedium: TextStyle(fontFamily: 'Inter', color: Color(0xFF334155)),
          bodySmall: TextStyle(fontFamily: 'Inter', color: Color(0xFF64748B)),
        ),
      ),
      home: Constants.hasSupabaseConfig
          ? const AuthGate()
          : const MissingConfigScreen(),
    );
  }
}

class MissingConfigScreen extends StatelessWidget {
  const MissingConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final missingKeys = Constants.missingSupabaseKeys.join(', ');

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuracion pendiente',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'La app necesita credenciales cargadas desde dart-define para iniciar Supabase.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Faltan: $missingKeys',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run --dart-define-from-file=dart_defines.json',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: SizedBox.shrink(),
          );
        }

        if (session != null) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) {
            return const LoginScreen();
          }

          return FutureBuilder<RegistrationGateState>(
            future: RegistrationGateService.evaluateGateState(user: user),
            builder: (context, gateSnapshot) {
              if (gateSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: SizedBox.shrink(),
                );
              }

              final gateState =
                  gateSnapshot.data ?? RegistrationGateState.incomplete;
              if (gateState == RegistrationGateState.complete) {
                return const HomeScreen();
              }
              return const RegistrationChecklistScreen();
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}
