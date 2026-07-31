import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Step1OtpScreen extends StatefulWidget {
  final String email;
  const Step1OtpScreen({super.key, required this.email});

  @override
  State<Step1OtpScreen> createState() => _Step1OtpScreenState();
}

class _Step1OtpScreenState extends State<Step1OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;

  static const _primaryColor = Color(0xFF0D9488);
  static const _greyBg = Color(0xFFF8FAFC);

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _verifyOTP();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
  }

  Future<void> _verifyOTP() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != 6) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.email,
      );

      if (mounted) {
        if (response.session != null) {
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al verificar sesión.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Código incorrecto o expirado'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        // Clear all fields
        for (var c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              // App Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.black87,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Confirmar Código',
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

              // Content
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: _primaryColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mark_email_read_outlined,
                                color: _primaryColor,
                                size: 32,
                              ),
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
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                                children: [
                                  const TextSpan(text: 'Lo enviamos a '),
                                  TextSpan(
                                    text: widget.email,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const TextSpan(
                                    text:
                                        '. Si no lo encuentras, revisa la carpeta de spam.',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 36),

                            // OTP Boxes
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(6, (index) {
                                  return Container(
                                    width: 42,
                                    height: 52,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: TextField(
                                      controller: _controllers[index],
                                      focusNode: _focusNodes[index],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      maxLength: 1,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      decoration: InputDecoration(
                                        counterText: '',
                                        contentPadding: EdgeInsets.zero,
                                        filled: true,
                                        fillColor: const Color(0xFFFAFAFA),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                            color: _primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      onChanged: (value) =>
                                          _onChanged(value, index),
                                    ),
                                  );
                                }),
                              ),
                            ),

                            const SizedBox(height: 32),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _verifyOTP,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _primaryColor
                                      .withValues(alpha: 0.6),
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
                                        'Confirmar código',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Cambiar e-mail',
                                style: TextStyle(
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
