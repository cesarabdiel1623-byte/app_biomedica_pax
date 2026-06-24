import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in_lib;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';
import '../../core/theme/app_colors.dart';
import '../home/home_screen.dart';
import 'registration_flow/registration_checklist_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _emailFocused = false;
  bool _passwordFocused = false;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideUpAnim;
  late final Animation<Offset> _slideDownAnim;

  static const _primaryColor = AppColors.primary; // Teal de Go Medical
  static const _greyBg = AppColors.background;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUpAnim = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideDownAnim = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    _emailFocus.addListener(
      () => setState(() => _emailFocused = _emailFocus.hasFocus),
    );
    _passwordFocus.addListener(
      () => setState(() => _passwordFocused = _passwordFocus.hasFocus),
    );
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${error.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
          queryParams: {'prompt': 'select_account'},
        );
        return;
      }

      final googleSignIn = google_sign_in_lib.GoogleSignIn(
        clientId: Constants.androidClientId,
        serverClientId: Constants.webClientId,
      );

      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final googleUser = await googleSignIn.signIn();
      final googleAuth = await googleUser?.authentication;
      final accessToken = googleAuth?.accessToken;
      final idToken = googleAuth?.idToken;

      if (accessToken == null) throw 'No se encontró el Access Token.';
      if (idToken == null) throw 'No se encontró el ID Token.';

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null && googleUser != null) {
        final metadata = currentUser.userMetadata ?? {};
        if (metadata['full_name'] == null ||
            metadata['full_name'].toString().isEmpty) {
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(
              data: {
                'full_name': googleUser.displayName ?? '',
                'avatar_url': googleUser.photoUrl ?? '',
              },
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de Google: ${error.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _greyBg,
      ),
      child: Scaffold(
        backgroundColor: _greyBg,
        body: SingleChildScrollView(
          child: Stack(
            children: [
              // Header superior grande con degradado
              Container(
                height: size.height * 0.42,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF3F7373), // Ming
                      Color(0xFF768C45), // Palm Leaf
                      Color(0xFFC5D7D9), // Columbia Blue
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo integrado
                      SlideTransition(
                        position: _slideDownAnim,
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo.jpeg',
                                width: 85,
                                height: 85,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SlideTransition(
                        position: _slideDownAnim,
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: const Text(
                            'Go Medical',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40), // Espacio para la card
                    ],
                  ),
                ),
              ),
              
              // Card flotante superpuesta
              Container(
                margin: EdgeInsets.only(
                  top: size.height * 0.32, // Monta el header
                  left: 24,
                  right: 24,
                  bottom: 40,
                ),
                child: SlideTransition(
                  position: _slideUpAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '¡Bienvenido de nuevo!',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Inicia sesión para continuar',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Campo de Email
                          _buildInput(
                            controller: _emailController,
                            focusNode: _emailFocus,
                            isFocused: _emailFocused,
                            hint: 'Correo electrónico',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            onSubmit: () => FocusScope.of(context).requestFocus(_passwordFocus),
                          ),
                          const SizedBox(height: 16),

                          // Campo de Contraseña
                          _buildInput(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            isFocused: _passwordFocused,
                            hint: 'Contraseña',
                            icon: Icons.lock_outline,
                            obscure: _obscurePassword,
                            suffix: IconButton(
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                            ),
                            onSubmit: _isLoading ? null : _signIn,
                          ),

                          // Olvidé mi contraseña
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.only(top: 8, bottom: 24),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '¿Olvidaste tu contraseña?',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),

                          // Botón Principal
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _signIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text(
                                      'INICIAR SESIÓN',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Separador O
                          Row(
                            children: [
                              const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'O',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Botón Google
                          SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _googleSignIn,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.border, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CustomPaint(painter: _ExactGoogleLogoPainter()),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Continuar con Google',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Registrarse Link
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              const Text('¿No tienes cuenta? ', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (context) => const RegistrationChecklistScreen()),
                                  );
                                },
                                child: const Text(
                                  'Regístrate aquí',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isFocused,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
    VoidCallback? onSubmit,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        border: Border.all(
          color: isFocused ? _primaryColor : AppColors.border.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: isFocused ? _primaryColor : AppColors.textSecondary,
            size: 20,
          ),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _ExactGoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final bluePath = Path()
      ..moveTo(22.56, 12.25)
      ..cubicTo(22.56, 11.47, 22.49, 10.72, 22.36, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.26)
      ..lineTo(17.92, 14.26)
      ..cubicTo(17.66, 15.63, 16.88, 16.79, 15.71, 17.57)
      ..lineTo(15.71, 20.34)
      ..lineTo(19.28, 20.34)
      ..cubicTo(21.36, 18.42, 22.56, 15.6, 22.56, 12.25)
      ..close();

    final greenPath = Path()
      ..moveTo(12.0, 23.0)
      ..cubicTo(14.97, 23.0, 17.46, 22.02, 19.28, 20.34)
      ..lineTo(15.71, 17.57)
      ..cubicTo(14.73, 18.23, 13.48, 18.63, 12.0, 18.63)
      ..cubicTo(9.14, 18.63, 6.71, 16.7, 5.84, 14.1)
      ..lineTo(2.18, 14.1)
      ..lineTo(2.18, 16.94)
      ..cubicTo(3.99, 20.53, 7.7, 23.0, 12.0, 23.0)
      ..close();

    final yellowPath = Path()
      ..moveTo(5.84, 14.1)
      ..cubicTo(5.62, 13.44, 5.49, 12.74, 5.49, 12.0)
      ..cubicTo(5.49, 11.26, 5.62, 10.56, 5.84, 9.9)
      ..lineTo(5.84, 7.07)
      ..lineTo(2.18, 7.07)
      ..cubicTo(1.43, 8.55, 1.0, 10.22, 1.0, 12.0)
      ..cubicTo(1.0, 13.78, 1.43, 15.45, 2.18, 16.94)
      ..lineTo(5.84, 14.1)
      ..close();

    final redPath = Path()
      ..moveTo(12.0, 5.38)
      ..cubicTo(13.62, 5.38, 15.06, 5.94, 16.21, 7.02)
      ..lineTo(19.36, 3.87)
      ..cubicTo(17.45, 2.09, 14.97, 1.0, 12.0, 1.0)
      ..cubicTo(7.7, 1.0, 3.99, 3.47, 2.18, 7.07)
      ..lineTo(5.84, 9.9)
      ..cubicTo(6.71, 7.3, 9.14, 5.38, 12.0, 5.38)
      ..close();

    canvas.drawPath(
      bluePath,
      Paint()
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      greenPath,
      Paint()
        ..color = const Color(0xFF34A853)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      yellowPath,
      Paint()
        ..color = const Color(0xFFFBBC05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      redPath,
      Paint()
        ..color = const Color(0xFFEA4335)
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
