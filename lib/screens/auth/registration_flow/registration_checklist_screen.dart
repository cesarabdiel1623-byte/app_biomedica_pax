import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'step_1_email.dart';
import 'step_2_name.dart';
import 'step_3_phone.dart';
import 'step_4_password.dart';

class RegistrationChecklistScreen extends StatefulWidget {
  const RegistrationChecklistScreen({super.key});

  @override
  State<RegistrationChecklistScreen> createState() => _RegistrationChecklistScreenState();
}

class _RegistrationChecklistScreenState extends State<RegistrationChecklistScreen>
    with SingleTickerProviderStateMixin {

  bool _emailValidated = false;
  bool _nameCompleted = false;
  bool _phoneValidated = false;
  bool _passwordCreated = false;
  bool _termsAccepted = false;

  String _userEmail = '';
  String _userName = '';
  String _userPhone = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const _primaryColor = Color(0xFF0D9488);
  static const _greyBg = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadExistingProgress();
  }

  /// Loads existing user data to restore registration progress after page reload
  void _loadExistingProgress() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata ?? {};
    final isGoogleUser = user.appMetadata['provider'] == 'google';

    setState(() {
      // Step 1: Email is validated if user has a session (they verified OTP)
      if (user.email != null && user.email!.isNotEmpty) {
        _emailValidated = true;
        _userEmail = user.email!;
      }

      // Step 2: Name is completed if full_name exists
      final fullName = metadata['full_name'] as String?;
      if (fullName != null && fullName.isNotEmpty) {
        _nameCompleted = true;
        _userName = fullName;
      }

      // Step 3: Phone is validated if phone exists or was skipped
      if ((user.phone != null && user.phone!.isNotEmpty) || metadata['phone_skipped'] == true) {
        _phoneValidated = true;
        _userPhone = (user.phone != null && user.phone!.isNotEmpty)
            ? user.phone!
            : 'Omitido - verificar después';
      }

      // Step 4: Google users don't need a password (they use Google to sign in)
      if (isGoogleUser) {
        _passwordCreated = true;
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Returns the current step index (0-3) based on completed steps
  int get _currentStep {
    if (!_emailValidated) return 0;
    if (!_nameCompleted) return 1;
    if (!_phoneValidated) return 2;
    if (!_passwordCreated) return 3;
    return 4; // All done
  }

  bool get _allCompleted => _emailValidated && _nameCompleted && _phoneValidated && _passwordCreated;

  Widget _buildStepItem({
    required int stepIndex,
    required IconData icon,
    required String title,
    required String completedTitle,
    required String subtitle,
    required String completedSubtitle,
    required bool isCompleted,
    required Future<void> Function() onTap,
    String buttonText = 'Completar',
  }) {
    final bool isActive = stepIndex == _currentStep;
    final bool isLocked = stepIndex > _currentStep;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: isCompleted
            ? const Color(0xFFF0FDF9)
            : isActive
                ? Colors.white
                : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? _primaryColor.withValues(alpha: 0.3)
              : isActive
                  ? _primaryColor.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.15),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? _primaryColor.withValues(alpha: 0.1)
                  : isActive
                      ? _primaryColor.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.08),
            ),
            child: isCompleted
                ? const Icon(Icons.check_circle, color: _primaryColor, size: 28)
                : Icon(
                    icon,
                    color: isActive ? _primaryColor : Colors.grey.shade400,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 16),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCompleted ? completedTitle : title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isLocked ? Colors.grey.shade400 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCompleted ? completedSubtitle : subtitle,
                  style: TextStyle(
                    color: isCompleted ? _primaryColor : Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Button or lock
          if (isCompleted)
            const Icon(Icons.check, color: _primaryColor, size: 22)
          else if (isActive)
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: () => onTap(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(buttonText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            )
          else
            Icon(Icons.lock_outline, color: Colors.grey.shade300, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: _primaryColor, brightness: Brightness.light),
        scaffoldBackgroundColor: _greyBg,
      ),
      child: Scaffold(
        backgroundColor: _greyBg,
        body: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Navigator.canPop(context)
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        : IconButton(
                            icon: const Icon(Icons.logout, color: Colors.red, size: 20),
                            tooltip: 'Cerrar sesión',
                            onPressed: () async {
                              await Supabase.instance.client.auth.signOut();
                            },
                          ),
                    Expanded(
                      child: Text(
                        Navigator.canPop(context) ? 'Crear Cuenta' : 'Completa tu registro',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Progress indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _currentStep / 4,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
                    minHeight: 4,
                  ),
                ),
              ),

              // Content
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Tus datos',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Valida tus datos para crear tu cuenta de forma segura.',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 28),

                              // Step 1: Email
                              _buildStepItem(
                                stepIndex: 0,
                                icon: Icons.email_outlined,
                                title: 'Validar e-mail',
                                completedTitle: 'E-mail validado',
                                subtitle: 'Lo usarás para recuperar tu cuenta.',
                                completedSubtitle: _userEmail,
                                isCompleted: _emailValidated,
                                buttonText: 'Validar',
                                onTap: () async {
                                  final result = await Navigator.of(context).push<Map<String, dynamic>>(
                                    MaterialPageRoute(builder: (context) => const Step1EmailScreen()),
                                  );
                                  if (result != null && result['success'] == true) {
                                    setState(() {
                                      _emailValidated = true;
                                      _userEmail = result['email'] ?? '';
                                    });
                                  }
                                },
                              ),

                              // Step 2: Name
                              _buildStepItem(
                                stepIndex: 1,
                                icon: Icons.person_outline,
                                title: 'Completar nombre',
                                completedTitle: 'Nombre completado',
                                subtitle: 'Elige cómo quieres que te llamemos.',
                                completedSubtitle: _userName,
                                isCompleted: _nameCompleted,
                                onTap: () async {
                                  final result = await Navigator.of(context).push<Map<String, dynamic>>(
                                    MaterialPageRoute(builder: (context) => const Step2NameScreen()),
                                  );
                                  if (result != null && result['success'] == true) {
                                    setState(() {
                                      _nameCompleted = true;
                                      _userName = result['name'] ?? '';
                                    });
                                  }
                                },
                              ),

                              // Step 3: Phone
                              _buildStepItem(
                                stepIndex: 2,
                                icon: Icons.phone_android_outlined,
                                title: 'Validar teléfono',
                                completedTitle: 'Teléfono validado',
                                subtitle: 'Servirá para ingresar a tu cuenta.',
                                completedSubtitle: _userPhone,
                                isCompleted: _phoneValidated,
                                buttonText: 'Validar',
                                onTap: () async {
                                  final result = await Navigator.of(context).push<Map<String, dynamic>>(
                                    MaterialPageRoute(builder: (context) => const Step3PhoneScreen()),
                                  );
                                  if (result != null && result['success'] == true) {
                                    setState(() {
                                      _phoneValidated = true;
                                      _userPhone = result['phone'] ?? '';
                                      if (_userPhone.isEmpty || result['skipped'] == true) {
                                        _userPhone = 'Omitido - verificar después';
                                      }
                                    });
                                  }
                                },
                              ),

                              // Step 4: Password
                              _buildStepItem(
                                stepIndex: 3,
                                icon: Icons.lock_outline,
                                title: 'Crear contraseña',
                                completedTitle: 'Contraseña creada',
                                subtitle: 'Servirá para ingresar a tu cuenta.',
                                completedSubtitle: '••••••••',
                                isCompleted: _passwordCreated,
                                buttonText: 'Crear',
                                onTap: () async {
                                  final result = await Navigator.of(context).push<Map<String, dynamic>>(
                                    MaterialPageRoute(
                                      builder: (context) => Step4PasswordScreen(userName: _userName),
                                    ),
                                  );
                                  if (result != null && result['success'] == true) {
                                    setState(() => _passwordCreated = true);
                                  }
                                },
                              ),

                              // Terms & Conditions (only when all steps are done)
                              if (_allCompleted) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: _termsAccepted,
                                          activeColor: _primaryColor,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          onChanged: (value) {
                                            setState(() => _termsAccepted = value ?? false);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                                          child: RichText(
                                            text: TextSpan(
                                              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                                              children: [
                                                const TextSpan(text: 'Autorizo el uso de mis datos de acuerdo a la '),
                                                TextSpan(
                                                  text: 'Declaración de Privacidad',
                                                  style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w600),
                                                ),
                                                const TextSpan(text: ' y acepto los '),
                                                TextSpan(
                                                  text: 'Términos y condiciones.',
                                                  style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _termsAccepted
                                        ? () async {
                                            // Save terms acceptance in user metadata
                                            await Supabase.instance.client.auth.updateUser(
                                              UserAttributes(data: {'terms_accepted': true}),
                                            );
                                            // Refresh session so AuthGate detects completed registration
                                            await Supabase.instance.client.auth.refreshSession();
                                            if (mounted && Navigator.canPop(context)) {
                                              Navigator.of(context).pop();
                                            }
                                            // If rendered by AuthGate, the stream rebuild will show HomeScreen
                                          }
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryColor,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: Colors.grey.shade300,
                                      disabledForegroundColor: Colors.grey.shade500,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    ),
                                    child: const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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
}
