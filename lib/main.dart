import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'models/payment_test_result.dart';
import 'screens/payment/payment_result_screen.dart';
import 'services/payment_deep_link_service.dart';
import 'utils/constants.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/registration_flow/registration_checklist_screen.dart';
import 'services/notification_service.dart';
import 'services/quote_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Constants.init();

  // Inicializar cotizaciones locales
  try {
    await QuoteService.init();
  } catch (e) {
    debugPrint('Error inicializando QuoteService: $e');
  }

  // Inicializar Supabase si tenemos las credenciales (por ahora puede fallar si están vacías,
  // inyectadas por dart-define / dart-define-from-file.
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

  // Inicializar notificaciones locales
  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Error inicializando NotificationService: $e');
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

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    await _paymentDeepLinkService.init(onResult: _showPaymentResult);
  }

  void _showPaymentResult(PaymentTestResult result) {
    if (_isNavigatingPaymentResult) return;

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

  @override
  void dispose() {
    _paymentDeepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Go Medical',
      debugShowCheckedModeBanner: false,
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
    FlutterNativeSplash.remove();
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
  /// Checks if user has completed all registration steps
  bool _isRegistrationComplete(User user) {
    final metadata = user.userMetadata ?? {};
    final hasName =
        metadata['full_name'] != null &&
        (metadata['full_name'] as String).isNotEmpty;
    final hasPhone = user.phone != null && user.phone!.isNotEmpty;
    final phoneSkipped = metadata['phone_skipped'] == true;
    final termsAccepted = metadata['terms_accepted'] == true;
    final isGoogleUser = user.appMetadata['provider'] == 'google';
    // Must have: name (or Google) + phone (or skipped) + terms accepted
    final phoneOk = hasPhone || phoneSkipped;
    if (isGoogleUser) return phoneOk && termsAccepted;
    return hasName && phoneOk && termsAccepted;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Use currentSession for the most up-to-date data
        // The stream is only used to trigger rebuilds
        final session = Supabase.instance.client.auth.currentSession;

        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        FlutterNativeSplash.remove();

        if (session != null) {
          // Use currentUser which has the latest metadata
          final user = Supabase.instance.client.auth.currentUser!;
          if (!_isRegistrationComplete(user)) {
            return const RegistrationChecklistScreen();
          }
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
