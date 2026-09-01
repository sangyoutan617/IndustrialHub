import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'models/profile.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/onboarding_screen.dart';
import 'services/notification_service.dart';
import 'services/profile_service.dart';
import 'services/session_prefs.dart';
import 'widgets/responsive_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrap();
}

Future<void> _bootstrap() async {
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  } catch (e, st) {
    debugPrint('startup: Supabase.initialize failed: $e\n$st');
    runApp(StartupErrorApp(onRetry: _bootstrap));
    return;
  }
  unawaited(NotificationService.instance.init());
  runApp(const MyApp());
}

class StartupErrorApp extends StatefulWidget {
  final Future<void> Function() onRetry;

  const StartupErrorApp({super.key, required this.onRetry});

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Couldn\'t start Industrial Hub',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'We couldn\'t connect to set things up. Check your internet '
                  'connection and try again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _retrying ? null : _retry,
                  icon: _retrying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_retrying ? 'Retrying…' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          ResponsiveShell(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Session? _initialSession =
      Supabase.instance.client.auth.currentSession;
  bool _checkedRememberMe = false;

  bool _isRecoveringPassword = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _isRecoveringPassword = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          setState(() => _isRecoveringPassword = false);
        }
      },
      onError: (error, stackTrace) {
        if (!mounted || error is! AuthException) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This link is invalid or has expired. Please request a new one.',
            ),
          ),
        );
      },
    );
    _enforceRememberMeWindow();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _enforceRememberMeWindow() async {
    try {
      final pendingRecovery =
          await SessionPrefs.consumePendingPasswordRecovery();
      final pendingOAuthChoice =
          await SessionPrefs.consumePendingOAuthRememberMe();
      if (pendingRecovery) {
        if (mounted) setState(() => _isRecoveringPassword = true);
      } else if (pendingOAuthChoice != null) {
        await SessionPrefs.setRememberMe(pendingOAuthChoice);
      } else if (_initialSession != null && !_isRecoveringPassword) {
        final stayLoggedIn = await SessionPrefs.shouldStayLoggedIn();
        if (!stayLoggedIn) {
          await Supabase.instance.client.auth.signOut();
        }
      }
    } catch (e, st) {
      debugPrint('auth: remember-me check failed: $e\n$st');
    } finally {
      if (mounted) setState(() => _checkedRememberMe = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedRememberMe) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, _initialSession),
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        if (_isRecoveringPassword) return const ResetPasswordScreen();
        return const OnboardingGate();
      },
    );
  }
}

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  final _profileService = ProfileService();
  late final Future<Profile?> _future = _profileService.getMyProfile();
  bool _justCompleted = false;

  @override
  Widget build(BuildContext context) {
    if (_justCompleted) return const HomeScreen();
    return FutureBuilder<Profile?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snapshot.data;
        if (snapshot.hasError || profile == null || profile.onboarded) {
          return const HomeScreen();
        }
        return OnboardingScreen(
          onComplete: () => setState(() => _justCompleted = true),
        );
      },
    );
  }
}
