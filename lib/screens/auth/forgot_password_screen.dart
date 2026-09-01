import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/session_prefs.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/status.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    setState(() => _isLoading = true);
    try {
      final isRegistered = await _authService.isEmailRegistered(email);
      if (!isRegistered) {
        _showError('This email is not registered. Please sign up first.');
        return;
      }
      await _authService.sendPasswordReset(email);
      await SessionPrefs.markPendingPasswordRecovery();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset link sent — check your email.')),
      );
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not process that request. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: AuthFormShell(
        formKey: _formKey,
        children: [
          const AuthHeader(
            icon: Icons.lock_reset,
            title: 'Forgot your password?',
            subtitle: "Enter your email and we'll send you a reset link.",
          ),
          const SizedBox(height: AppSpacing.xl),
          const InfoBanner(
            status: AppStatus.info,
            title: 'Signed up with Google?',
            message:
                "You don't need a reset link — go back and use Continue "
                "with Google. Setting a password here also works: you'll "
                'then be able to sign in either way.',
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Email is required';
              }
              if (!value.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Send reset link'),
          ),
          const SizedBox(height: AppSpacing.l),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Back to log in',
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
