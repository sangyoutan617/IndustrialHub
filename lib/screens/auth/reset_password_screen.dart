import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSaving = false;
  bool _isCancelling = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _authService.updatePassword(_passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password updated. You can now sign in with your email and '
            'password.',
          ),
        ),
      );
      await _authService.signOut();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not update the password. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _isCancelling = true);
    try {
      await _authService.signOut();
    } finally {
      if (mounted) setState(() => _isCancelling = false);
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
    final busy = _isSaving || _isCancelling;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set a new password')),
      body: AuthFormShell(
        formKey: _formKey,
        children: [
          const AuthHeader(icon: Icons.password, title: 'Choose a new password'),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'At least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.l),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Update password'),
          ),
          const SizedBox(height: AppSpacing.l),
          Center(
            child: TextButton(
              onPressed: busy ? null : _cancel,
              child: Text(
                'Cancel and sign out',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
