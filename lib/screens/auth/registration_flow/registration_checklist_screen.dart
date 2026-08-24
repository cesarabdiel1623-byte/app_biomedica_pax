import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/registration_draft.dart';
import '../../../services/registration_gate_service.dart';
import '../../../utils/ui_helpers.dart';
import '../../home/home_screen.dart';
import '../otp_verification_screen.dart';
import 'step_1_email.dart';
import 'step_2_name.dart';
import 'step_3_phone.dart';
import 'step_4_password.dart';

class RegistrationChecklistScreen extends StatefulWidget {
  const RegistrationChecklistScreen({super.key});

  @override
  State<RegistrationChecklistScreen> createState() =>
      _RegistrationChecklistScreenState();
}

class _RegistrationChecklistScreenState
    extends State<RegistrationChecklistScreen>
    with SingleTickerProviderStateMixin {
  final RegistrationDraft _draft = RegistrationDraft();

  bool _emailValidated = false;
  bool _nameCompleted = false;
  bool _phoneValidated = false;
  bool _passwordCreated = false;
  bool _termsAccepted = false;
  bool _isGoogle = false;
  bool _isCompleting = false;

  String _userEmail = '';
  String _userName = '';
  String _userPhone = '';
  String _userPassword = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const _primaryColor = Color(0xFF0D9488);
  static const _greyBg = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadExistingProgress();
  }

  /// Loads existing user data from authoritative DB and auth state if session exists
  Future<void> _loadExistingProgress() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isGoogle = false;
      });
      return;
    }

    final progress = await RegistrationGateService.loadOnboardingProgress(user: user);
    if (!mounted) return;

    setState(() {
      _emailValidated = progress.emailVerified;
      _nameCompleted = progress.nameCompleted;
      _phoneValidated = progress.phoneCompleted;
      _passwordCreated = progress.passwordCreated;
      _termsAccepted = progress.termsAccepted;
      _userEmail = progress.email;
      _userName = progress.fullName;
      _userPhone = progress.phone.isNotEmpty
          ? progress.phone
          : (progress.phoneCompleted ? 'Omitido - verificar después' : '');
      _isGoogle = progress.isGoogleUser;

      _draft.email = _userEmail;
      _draft.fullName = _userName;
      _draft.phone = progress.phone;
      _draft.phoneSkipped = progress.phoneCompleted && progress.phone.isEmpty;
      _draft.termsAccepted = _termsAccepted;
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _draft.clear();
    _userPassword = '';
    super.dispose();
  }

  /// Returns the current step index (0-3) based on completed steps
  int get _currentStep {
    if (!_emailValidated) return 0;
    if (!_nameCompleted) return 1;
    if (!_phoneValidated) return 2;
    if (!_isGoogle && !_passwordCreated) return 3;
    return 4; // All done
  }

  bool get _allCompleted {
    if (!_emailValidated || !_nameCompleted || !_phoneValidated) return false;
    if (!_isGoogle && !_passwordCreated) return false;
    return true;
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isCompleted
            ? const Color(0xFFF0FDF9)
            : isActive
            ? Colors.white
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted
              ? _primaryColor.withValues(alpha: 0.3)
              : isActive
              ? _primaryColor.withValues(alpha: 0.4)
              : Colors.grey.withValues(alpha: 0.15),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon circle
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? _primaryColor.withValues(alpha: 0.1)
                      : isActive
                      ? _primaryColor.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.08),
                ),
                child: isCompleted
                    ? const Icon(
                        Icons.check_circle,
                        color: _primaryColor,
                        size: 22,
                      )
                    : Icon(
                        icon,
                        color: isActive ? _primaryColor : Colors.grey.shade400,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 12),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCompleted ? completedTitle : title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? Colors.grey.shade400 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCompleted ? completedSubtitle : subtitle,
                      style: TextStyle(
                        color: isCompleted
                            ? _primaryColor
                            : Colors.grey.shade500,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (isCompleted)
                const Icon(Icons.check, color: _primaryColor, size: 20)
              else if (isLocked)
                Icon(Icons.lock_outline, color: Colors.grey.shade300, size: 18),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: () => onTap(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleFinalSubmission() async {
    if (!_termsAccepted || _isCompleting) return;

    setState(() => _isCompleting = true);
    final user = Supabase.instance.client.auth.currentUser;

    try {
      if (user == null) {
        // REGISTRO EMAIL NORMAL: Crear cuenta por primera vez
        final authRes = await Supabase.instance.client.auth.signUp(
          email: _userEmail.trim(),
          password: _userPassword,
          data: {
            'full_name': _userName.trim(),
          },
        );

        if (!mounted) return;

        if (authRes.session != null) {
          // Sesión activa inmediata -> finalizar onboarding
          await RegistrationGateService.completeOnboarding(
            fullName: _userName.trim(),
            phone: _userPhone.startsWith('Omitido') ? null : _userPhone,
            phoneSkipped: _userPhone.startsWith('Omitido'),
          );

          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          }
        } else {
          // Confirmación requerida -> Pantalla de código OTP
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => OTPVerificationScreen(
                  email: _userEmail.trim(),
                  fullName: _userName.trim(),
                  phone: _userPhone.startsWith('Omitido') ? null : _userPhone,
                  phoneSkipped: _userPhone.startsWith('Omitido'),
                ),
              ),
            );
          }
        }
      } else {
        // USUARIO YA AUTENTICADO (Google o sesión existente): Finalizar onboarding
        final ok = await RegistrationGateService.completeOnboarding(
          fullName: _userName.trim(),
          phone: _userPhone.startsWith('Omitido') ? null : _userPhone,
          phoneSkipped: _userPhone.startsWith('Omitido'),
        );

        if (!mounted) return;

        if (ok) {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al finalizar registro. Por favor intenta de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                            icon: const Icon(
                              Icons.arrow_back_ios_new,
                              color: Colors.black87,
                              size: 20,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.red,
                              size: 20,
                            ),
                            tooltip: 'Cerrar sesión',
                            onPressed: () async {
                              await Supabase.instance.client.auth.signOut();
                            },
                          ),
                    Expanded(
                      child: Text(
                        Navigator.canPop(context)
                            ? 'Crear Cuenta'
                            : 'Completa tu registro',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      _primaryColor,
                    ),
                    minHeight: 4,
                  ),
                ),
              ),

              // Content
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Container(
                          padding: const EdgeInsets.all(18),
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
                                'Completa tus datos',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ingresa la información requerida para crear tu cuenta de forma segura.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Step 1: Email
                              _buildStepItem(
                                stepIndex: 0,
                                icon: Icons.email_outlined,
                                title: 'Ingresar e-mail',
                                completedTitle: 'E-mail ingresado',
                                subtitle: 'Lo usarás como tu usuario de acceso.',
                                completedSubtitle: 'Guardado',
                                isCompleted: _emailValidated,
                                buttonText: 'Ingresar',
                                onTap: () async {
                                  final result = await Navigator.of(context)
                                      .push<Map<String, dynamic>>(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const Step1EmailScreen(),
                                        ),
                                      );
                                  if (result != null &&
                                      result['success'] == true) {
                                    setState(() {
                                      _emailValidated = true;
                                      _userEmail = result['email'] ?? '';
                                      _draft.email = _userEmail;
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
                                completedSubtitle: 'Guardado',
                                isCompleted: _nameCompleted,
                                buttonText: 'Completar',
                                onTap: () async {
                                  final result = await Navigator.of(context)
                                      .push<Map<String, dynamic>>(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const Step2NameScreen(),
                                        ),
                                      );
                                  if (result != null &&
                                      result['success'] == true) {
                                    setState(() {
                                      _nameCompleted = true;
                                      _userName = result['name'] ?? '';
                                      _draft.fullName = _userName;
                                    });
                                  }
                                },
                              ),

                              // Step 3: Phone
                              _buildStepItem(
                                stepIndex: 2,
                                icon: Icons.phone_android_outlined,
                                title: 'Teléfono de contacto',
                                completedTitle: 'Teléfono ingresado',
                                subtitle: 'Para coordinar envíos y notificaciones.',
                                completedSubtitle:
                                    _userPhone.startsWith('Omitido')
                                    ? 'Omitido por ahora'
                                    : 'Guardado',
                                isCompleted: _phoneValidated,
                                buttonText: 'Ingresar',
                                onTap: () async {
                                  final result = await Navigator.of(context)
                                      .push<Map<String, dynamic>>(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const Step3PhoneScreen(),
                                        ),
                                      );
                                  if (result != null &&
                                      result['success'] == true) {
                                    setState(() {
                                      _phoneValidated = true;
                                      _userPhone = result['phone'] ?? '';
                                      if (_userPhone.isEmpty ||
                                          result['skipped'] == true) {
                                        _userPhone =
                                            'Omitido - verificar después';
                                        _draft.phoneSkipped = true;
                                        _draft.phone = '';
                                      } else {
                                        _draft.phone = _userPhone;
                                        _draft.phoneSkipped = false;
                                      }
                                    });
                                    if (mounted) {
                                      if (result['skipped'] == true) {
                                        UiHelpers.showFloatingSuccessToast(
                                          context,
                                          'Teléfono omitido por ahora.',
                                        );
                                      } else {
                                        UiHelpers.showFloatingSuccessToast(
                                          context,
                                          '¡Teléfono guardado!',
                                        );
                                      }
                                    }
                                  }
                                },
                              ),

                              // Step 4: Password (solo para email/password)
                              if (!_isGoogle)
                                _buildStepItem(
                                  stepIndex: 3,
                                  icon: Icons.lock_outline,
                                  title: 'Crear contraseña',
                                  completedTitle: 'Contraseña creada',
                                  subtitle: 'Servirá para ingresar a tu cuenta.',
                                  completedSubtitle: 'Guardada',
                                  isCompleted: _passwordCreated,
                                  buttonText: 'Crear',
                                  onTap: () async {
                                    final result = await Navigator.of(context)
                                        .push<Map<String, dynamic>>(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                Step4PasswordScreen(
                                                  userName: _userName,
                                                ),
                                          ),
                                        );
                                    if (result != null &&
                                        result['success'] == true) {
                                      setState(() {
                                        _passwordCreated = true;
                                        _userPassword = result['password'] ?? '';
                                        _draft.password = _userPassword;
                                      });
                                      if (mounted) {
                                        UiHelpers.showFloatingSuccessToast(
                                          context,
                                          '¡Contraseña lista!',
                                        );
                                      }
                                    }
                                  },
                                ),

                              // Terms & Conditions (only when all steps are done)
                              if (_allCompleted) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Checkbox(
                                          value: _termsAccepted,
                                          activeColor: _primaryColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              _termsAccepted = value ?? false;
                                              _draft.termsAccepted = _termsAccepted;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => setState(() {
                                            _termsAccepted = !_termsAccepted;
                                            _draft.termsAccepted = _termsAccepted;
                                          }),
                                          child: RichText(
                                            text: TextSpan(
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black87,
                                                height: 1.3,
                                              ),
                                              children: [
                                                const TextSpan(
                                                  text:
                                                      'Autorizo el uso de mis datos de acuerdo a la ',
                                                ),
                                                TextSpan(
                                                  text:
                                                      'Declaración de Privacidad',
                                                  style: TextStyle(
                                                    color: _primaryColor,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const TextSpan(
                                                  text: ' y acepto los ',
                                                ),
                                                TextSpan(
                                                  text:
                                                      'Términos y condiciones.',
                                                  style: TextStyle(
                                                    color: _primaryColor,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _termsAccepted && !_isCompleting
                                        ? _handleFinalSubmission
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryColor,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade300,
                                      disabledForegroundColor:
                                          Colors.grey.shade500,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    child: _isCompleting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            _isGoogle ? 'Continuar' : 'Crear cuenta',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
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
