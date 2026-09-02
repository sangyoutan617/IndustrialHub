import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/session_prefs.dart';
import '../../widgets/auth_scaffold.dart';
import '../admin/admin_login_screen.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await SessionPrefs.setRememberMe(_rememberMe);
    } on AuthException catch (e) {
      if (e.message == 'Invalid login credentials') {
        _showError(
          'Invalid login credentials. If you signed up with Google, use '
          'Continue with Google instead.',
        );
      } else {
        _showError(e.message);
      }
    } catch (e) {
      _showError('Unable to sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await SessionPrefs.markPendingOAuthRememberMe(_rememberMe);
      await _authService.signInWithGoogle();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Unable to sign in with Google. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AuthFormShell(
        formKey: _formKey,
        children: [
          AuthHeader(
            icon: Icons.factory,
            title: 'Industrial Hub',
            subtitle: l10n.tagline,
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10n.authEmail,
              prefixIcon: const Icon(Icons.mail_outline),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.authEmailRequired;
              }
              if (!value.contains('@')) return l10n.authEmailInvalid;
              if (value.trim().toLowerCase() == AdminConfig.adminEmail) {
                return 'Use Admin login for this account';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.l),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: l10n.authPassword,
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
              if (value == null || value.isEmpty) {
                return l10n.authPasswordRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _rememberMe,
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(() => _rememberMe = value ?? false),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              GestureDetector(
                onTap: _isLoading
                    ? null
                    : () => setState(() => _rememberMe = !_rememberMe),
                child: Text(
                  l10n.authRememberMe,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
              child: Text(l10n.authForgotPassword),
            ),
          ),
          const SizedBox(height: 4),
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
                : Text(l10n.authLogIn),
          ),
          const SizedBox(height: AppSpacing.l),
          const AuthOrDivider(),
          const SizedBox(height: AppSpacing.l),
          OutlinedButton.icon(
            onPressed: (_isLoading || _isGoogleLoading)
                ? null
                : _signInWithGoogle,
            icon: _isGoogleLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.g_mobiledata, size: 24),
            label: Text(l10n.authContinueWithGoogle),
          ),
          const SizedBox(height: AppSpacing.xl - 4),
          Center(
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    ),
              child: RichText(
                text: TextSpan(
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  children: [
                    TextSpan(text: l10n.authNoAccount),
                    TextSpan(
                      text: l10n.authSignUp,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                    ),
              child: Text(
                l10n.authAdminLogin,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
