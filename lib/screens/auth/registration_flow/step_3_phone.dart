import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/cart_service.dart';

class Step3PhoneScreen extends StatefulWidget {
  const Step3PhoneScreen({super.key});

  @override
  State<Step3PhoneScreen> createState() => _Step3PhoneScreenState();
}

class _Step3PhoneScreenState extends State<Step3PhoneScreen> {
  final _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _whatsappOptIn = true;

  // States: 'input', 'otp', 'success'
  String _currentView = 'input';
  String _fullPhone = '';

  static const _primaryColor = Color(0xFF0D9488);
  static const _greyBg = Color(0xFFF8FAFC);

  Future<void> _sendSmsOtp() async {
    final phone = _phoneController.text.trim().replaceAll(' ', '');
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un número de teléfono válido (10 dígitos)'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _fullPhone = phone.startsWith('+') ? phone : '+52$phone';

    try {
      // 1. Normalizar y validar teléfono antes de enviar SMS (primera capa en Flutter)
      final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final isRegistered = await CartService.isPhoneRegistered(normalized);
      if (isRegistered) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este número ya está registrado en una cuenta de la app. Inicia sesión o recupera tu cuenta.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(phone: _fullPhone),
      );
      if (mounted) {
        setState(() {
          _currentView = 'otp';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = _parsePhoneError(e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg, style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  /// Translate common SMS/Twilio errors to user-friendly Spanish
  String _parsePhoneError(String error) {
    final e = error.toLowerCase();
    if (e.contains('exceeded') && e.contains('daily')) {
      return 'Se alcanzó el límite diario de SMS. Intenta nuevamente mañana o contacta soporte.';
    } else if (e.contains('sms_send_failed')) {
      return 'No se pudo enviar el SMS. Verifica tu número e intenta más tarde.';
    } else if (e.contains('invalid') && e.contains('phone')) {
      return 'El número de teléfono no es válido. Verifica que sea correcto.';
    } else if (e.contains('too_many_requests') || e.contains('rate_limit')) {
      return 'Demasiados intentos. Espera unos minutos antes de intentar de nuevo.';
    } else if (e.contains('network') || e.contains('timeout')) {
      return 'Error de conexión. Verifica tu internet e intenta de nuevo.';
    } else if (e.contains('not_authorized') || e.contains('unauthorized')) {
      return 'No autorizado. Inicia sesión nuevamente.';
    }
    return 'Error al enviar SMS. Intenta más tarde o contacta soporte.';
  }

  void _onOtpChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 5) {
        _otpFocusNodes[index + 1].requestFocus();
      } else {
        _otpFocusNodes[index].unfocus();
        _verifyOtp();
      }
    } else if (index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length != 6) return;

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: _fullPhone,
        token: code,
        type: OtpType.phoneChange,
      );

      // Save WhatsApp opt-in preference
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'whatsapp_opt_in': _whatsappOptIn}),
      );

      if (mounted) {
        setState(() {
          _currentView = 'success';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Código incorrecto o expirado'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        for (var c in _otpControllers) {
          c.clear();
        }
        _otpFocusNodes[0].requestFocus();
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.black87,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    else
                      const SizedBox(width: 48),
                    const Expanded(
                      child: Text(
                        'Validar Teléfono',
                        style: TextStyle(
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
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
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
                        child: _currentView == 'input'
                            ? _buildPhoneInput()
                            : _currentView == 'otp'
                            ? _buildOtpInput()
                            : _buildSuccess(),
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

  Widget _buildPhoneInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.phone_android_outlined,
            color: _primaryColor,
            size: 32,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Ingresa tu teléfono',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Te enviaremos un código por SMS para verificarlo.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Número de teléfono',
            prefixIcon: const Icon(Icons.phone_outlined, color: _primaryColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendSmsOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _primaryColor.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
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
                    'Enviar código SMS',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Skip button
        TextButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            try {
              await Supabase.instance.client.auth.updateUser(
                UserAttributes(data: {'phone_skipped': true}),
              );
            } catch (_) {}
            navigator.pop({
              'success': true,
              'phone': 'Omitido',
              'skipped': true,
            });
          },
          child: Text(
            'Omitir por ahora',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.sms_outlined, color: _primaryColor, size: 32),
        ),
        const SizedBox(height: 24),
        const Text(
          'Ingresa el código',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            children: [
              const TextSpan(text: 'Enviamos un SMS a '),
              TextSpan(
                text: _fullPhone,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            6,
            (i) => SizedBox(
              width: 46,
              height: 56,
              child: TextField(
                controller: _otpControllers[i],
                focusNode: _otpFocusNodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _primaryColor,
                      width: 2,
                    ),
                  ),
                ),
                onChanged: (v) => _onOtpChanged(v, i),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _primaryColor.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
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
                    'Verificar código',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _currentView = 'input'),
          child: const Text(
            'Cambiar número',
            style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle, color: _primaryColor, size: 48),
        ),
        const SizedBox(height: 24),
        const Text(
          'Validamos tu teléfono',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _fullPhone,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _whatsappOptIn,
                  activeColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (v) => setState(() => _whatsappOptIn = v ?? false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _whatsappOptIn = !_whatsappOptIn),
                  child: const Text(
                    'Acepto recibir promociones y novedades por WhatsApp y/o SMS.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.of(
              context,
            ).pop({'success': true, 'phone': _fullPhone}),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Continuar',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
