import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_scaffold.dart';

class VerifyResetCodeScreen extends StatefulWidget {
  final String email;

  const VerifyResetCodeScreen({super.key, required this.email});

  @override
  State<VerifyResetCodeScreen> createState() => _VerifyResetCodeScreenState();
}

class _VerifyResetCodeScreenState extends State<VerifyResetCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isVerifying = true);
    try {
      await _authService.verifyPasswordResetCode(
        email: widget.email,
        code: _codeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not verify that code. Please try again.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await _authService.sendPasswordReset(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('A new code has been sent.')));
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not resend the code. Please try again.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _isVerifying || _isResending;
    return Scaffold(
      appBar: AppBar(title: const Text('Enter code')),
      body: AuthFormShell(
        formKey: _formKey,
        children: [
          AuthHeader(
            icon: Icons.mark_email_read_outlined,
            title: 'Check your email',
            subtitle: 'We sent an 8-digit code to ${widget.email}.',
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: const InputDecoration(labelText: 'Code', counterText: ''),
            validator: (value) {
              if (value == null || value.trim().length != 8) {
                return 'Enter the 8-digit code from your email';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: busy ? null : _verify,
            child: _isVerifying
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Verify code'),
          ),
          const SizedBox(height: AppSpacing.l),
          Center(
            child: TextButton(
              onPressed: busy ? null : _resend,
              child: _isResending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      "Didn't get a code? Resend",
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.primary),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
