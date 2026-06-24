import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'otp_verification_screen.dart';
import '../../core/theme/app_colors.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  static const _primaryColor = AppColors.primary;

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || name.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor llena todos los campos')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => OTPVerificationScreen(email: email),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Header superior luminoso con degradado suave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.35,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF53A687), // primary
                    Color(0xFFC1D96C), // secondary
                    Color(0xFFDEF294), // softHighlight
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
            ),
          ),

          // AppBar transparente con botón de regreso blanco
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Contenido escroleable
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Medallón superior con ícono médico/usuario
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.local_hospital_outlined,
                          size: 56,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tarjeta blanca para el formulario
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Crear Cuenta',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Ingresa tu información para registrarte en Go Medical.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),

                            // Campo Nombre
                            TextField(
                              controller: _nameController,
                              style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Nombre Completo',
                                prefixIcon: const Icon(Icons.person_outline),
                                labelStyle: const TextStyle(color: AppColors.textSecondary),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: _primaryColor,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Campo Email
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Correo Electrónico',
                                prefixIcon: const Icon(Icons.email_outlined),
                                labelStyle: const TextStyle(color: AppColors.textSecondary),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: _primaryColor,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Campo Password
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Crear contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                labelStyle: const TextStyle(color: AppColors.textSecondary),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: _primaryColor,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Botón de Registro (Primary Color #53A687)
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signUp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      AppColors.primary.withOpacity(0.5),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Registrarse',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
