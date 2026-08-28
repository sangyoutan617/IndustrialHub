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

/// Initialises Supabase and launches the app. Isolated (and retryable) so a
/// failed init — bad config, no network on first launch — shows a friendly
/// retry screen instead of the blank/black screen that an exception thrown
/// before [runApp] used to leave behind.
Future<void> _bootstrap() async {
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      // Password-reset (and email-confirmation) links are opened from an
      // email client, which is almost never the same browser tab that
      // requested them. The default PKCE flow needs a code verifier stashed
      // in that original tab's local storage to complete the sign-in, so it
      // silently fails whenever the link is opened elsewhere — landing back
      // on the login screen with no session. Implicit flow carries the
      // session tokens directly in the redirect URL instead, so it works
      // regardless of which browser/tab opens the link.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  } catch (e, st) {
    debugPrint('startup: Supabase.initialize failed: $e\n$st');
    runApp(StartupErrorApp(onRetry: _bootstrap));
    return;
  }
  // Best-effort: sets up the local-notifications channel and asks for
  // permission over the running app. No-op on web. Not awaited so the
  // permission dialog never blocks first paint.
  unawaited(NotificationService.instance.init());
  runApp(const MyApp());
}

/// Standalone fallback shown when [Supabase.initialize] fails, so startup
/// can't reach [MyApp]. Deliberately self-contained — it depends on nothing
/// that initialisation set up — and offers a Retry that re-runs [_bootstrap].
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
    // On success this replaces the whole app via runApp, so this widget is
    // torn down and the flag never needs resetting; on failure _bootstrap
    // calls runApp(StartupErrorApp) again with a fresh state.
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
      // Follows the device's light/dark setting.
      themeMode: ThemeMode.system,
      // Follows the device locale — there's no in-app language picker.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Caps the content width so the app doesn't stretch edge to edge on
      // wide/landscape/desktop/web viewports. Applies to every screen and
      // dialog at once — see ResponsiveShell.
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

  // True while the current session came from a password-recovery link
  // rather than a normal sign-in — routes to ResetPasswordScreen instead
  // of HomeScreen until that flow explicitly signs out.
  bool _isRecoveringPassword = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Subscribed before _enforceRememberMeWindow runs so a
    // passwordRecovery event that arrives while that (async) check is
    // still in flight is never missed. In practice, on a fresh web page
    // load the event has usually already fired inside
    // Supabase.initialize() — before any listener could exist — which is
    // exactly why _enforceRememberMeWindow also checks the persisted
    // pending-recovery flag below; this listener is the fallback for a
    // warm app (e.g. a mobile deep link arriving while already running).
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _isRecoveringPassword = true);
        } else if (state.event == AuthChangeEvent.signedOut) {
          // Otherwise a later, completely normal sign-in would still be
          // misrouted to ResetPasswordScreen by a flag left over from an
          // earlier recovery flow.
          setState(() => _isRecoveringPassword = false);
        }
      },
      // A password-reset (or email-confirmation) link that's already been
      // used or has expired makes supabase_flutter's own deep-link handler
      // push an AuthException onto this stream instead of a normal AuthState
      // — without this handler it surfaces to the user as nothing at all:
      // the app just silently lands back on the login screen. Confirmed live
      // on the Android emulator by firing a malformed recovery deep link at
      // the app and watching it throw unhandled.
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

  // "Remember me" is an app-level boundary on top of Supabase's own session
  // persistence: if the box wasn't checked at login (or the 30 days are up),
  // sign out on this cold start even though a valid session still exists.
  Future<void> _enforceRememberMeWindow() async {
    // Whatever happens below, the gate must stop showing the startup spinner
    // and fall through to the auth check — an exception here (a failed prefs
    // read or signOut) used to leave _checkedRememberMe false forever, which
    // pinned the app on the spinner with no way out. Failing open is safe:
    // a null session lands on LoginScreen, and the worst case (a session that
    // should have been signed out surviving) is far better than a dead app.
    try {
      // A password-recovery link also completes via a full page reload on
      // web, which looks identical to a stale restart to the check below —
      // consuming this flag (set by ForgotPasswordScreen right before the
      // email was sent) lets that reload's session survive long enough for
      // ResetPasswordScreen to use it, instead of being signed straight out.
      final pendingRecovery =
          await SessionPrefs.consumePendingPasswordRecovery();
      final pendingOAuthChoice =
          await SessionPrefs.consumePendingOAuthRememberMe();
      if (pendingRecovery) {
        if (mounted) setState(() => _isRecoveringPassword = true);
      } else if (pendingOAuthChoice != null) {
        // This cold start is a web OAuth redirect completing a sign-in that
        // just happened, not a real app restart — apply the choice made
        // before the redirect instead of treating it as a stale session.
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

/// Sits between a signed-in session and the home screen. A brand-new user
/// (profiles.onboarded == false) is sent through [OnboardingScreen] first;
/// everyone else goes straight to [HomeScreen]. If the profile can't be
/// read, the user is never trapped — they go to the home screen.
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
