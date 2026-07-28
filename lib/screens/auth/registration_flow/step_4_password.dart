import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Step4PasswordScreen extends StatefulWidget {
  final String userName;
  const Step4PasswordScreen({super.key, required this.userName});

  @override
  State<Step4PasswordScreen> createState() => _Step4PasswordScreenState();
}

class _Step4PasswordScreenState extends State<Step4PasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _passwordSaved = false;

  static const _primaryColor = Color(0xFF0D9488);
  static const _greyBg = Color(0xFFF8FAFC);

  // Validation rules
  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasLetterAndNumber =>
      RegExp(r'[a-zA-Z]').hasMatch(_passwordController.text) &&
      RegExp(r'[0-9]').hasMatch(_passwordController.text);
  bool get _hasSymbol =>
      RegExp(r'[!@#\$%\^&\*\?\-_\.,:;]').hasMatch(_passwordController.text);
  bool get _noName {
    final pw = _passwordController.text.toLowerCase();
    final parts = widget.userName.toLowerCase().split(' ');
    for (final part in parts) {
      if (part.length > 2 && pw.contains(part)) return false;
    }
    return true;
  }

  bool get _noSequence {
    final pw = _passwordController.text.toLowerCase();
    const sequences = [
      '1234',
      '2345',
      '3456',
      '4567',
      '5678',
      '6789',
      'abcd',
      'bcde',
      'cdef',
      'qwer',
      'asdf',
    ];
    for (final seq in sequences) {
      if (pw.contains(seq)) return false;
    }
    return true;
  }

  bool get _passwordsMatch =>
      _confirmController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;
  bool get _allValid =>
      _hasMinLength &&
      _hasLetterAndNumber &&
      _hasSymbol &&
      _noName &&
      _noSequence &&
      _passwordsMatch;

  Future<void> _savePassword() async {
    if (!_allValid) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

      setState(() {
        _passwordSaved = true;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRule(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.circle_outlined,
            color: isValid ? _primaryColor : Colors.grey.shade400,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isValid ? _primaryColor : Colors.grey.shade500,
                fontWeight: isValid ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
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
                        'Crear Contraseña',
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
                        child: _passwordSaved
                            ? _buildSuccessView()
                            : _buildPasswordForm(),
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

  Widget _buildPasswordForm() {
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
          child: const Icon(Icons.lock_outline, color: _primaryColor, size: 32),
        ),
        const SizedBox(height: 24),
        const Text(
          'Crea tu contraseña',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Ingresa una contraseña segura que no uses en otras plataformas.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Password field
        TextField(
          controller: _passwordController,
          obscureText: _obscure1,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Ingresa tu contraseña',
            prefixIcon: const Icon(Icons.lock_outline, color: _primaryColor),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure1
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _obscure1 = !_obscure1),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Rules
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRule(
                'Mínimo 8 caracteres con letras y números',
                _hasMinLength && _hasLetterAndNumber,
              ),
              _buildRule('Mínimo 1 signo o símbolo (?-!*\$#)', _hasSymbol),
              _buildRule('No incluyas tu nombre o apellido', _noName),
              _buildRule('Sin secuencias como 1234 o ABCD', _noSequence),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Confirm password field
        TextField(
          controller: _confirmController,
          obscureText: _obscure2,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Confirma tu contraseña',
            prefixIcon: Icon(
              _passwordsMatch ? Icons.check_circle : Icons.lock_outline,
              color: _passwordsMatch ? _primaryColor : Colors.grey,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure2
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _obscure2 = !_obscure2),
            ),
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
            onPressed: _allValid && !_isLoading ? _savePassword : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade500,
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
                    'Crear contraseña',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
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
          'Creaste tu contraseña',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Asegúrate de recordarla, la necesitarás para ingresar a tu cuenta.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop({'success': true}),
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
