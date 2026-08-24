import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The icon-badge + title + subtitle header repeated at the top of every
/// auth screen (login, signup, forgot/reset password). Theme-aware (reads
/// `colorScheme.primaryContainer`) so the badge stays legible in dark mode,
/// unlike the previous per-screen copies that hardcoded [AppColors.primary].
class AuthHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: AppSpacing.l),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The scrollable, centered, padded `Form` shell shared by every auth
/// screen. Screens supply their own fields/buttons as [children] — this
/// only standardizes the surrounding layout.
class AuthFormShell extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final List<Widget> children;

  const AuthFormShell({
    super.key,
    required this.formKey,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// The "or" divider between the email/password form and the Google
/// sign-in button, used on both login and signup.
class AuthOrDivider extends StatelessWidget {
  final String label;
  const AuthOrDivider({super.key, this.label = 'or'});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
