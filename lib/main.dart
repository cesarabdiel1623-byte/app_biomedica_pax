import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/constants.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/registration_flow/registration_checklist_screen.dart';
import 'services/notification_service.dart';
import 'services/quote_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar cotizaciones locales
  try {
    await QuoteService.init();
  } catch (e) {
    debugPrint('Error inicializando QuoteService: $e');
  }

  // Inicializar Supabase si tenemos las credenciales (por ahora puede fallar si están vacías,
  // pero lo preparamos para cuando el usuario ponga las reales).
  try {
    if (Constants.supabaseUrl != 'AQUI_TU_NUEVA_SUPABASE_URL') {
      await Supabase.initialize(
        url: Constants.supabaseUrl,
        anonKey: Constants.supabaseAnonKey,
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

class GoMedicalApp extends StatelessWidget {
  const GoMedicalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Go Medical',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D9488)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
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
    final hasName = metadata['full_name'] != null &&
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

        if (snapshot.connectionState == ConnectionState.waiting && session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

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
