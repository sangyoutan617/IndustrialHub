import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/session_prefs.dart';
import 'widgets/responsive_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Industrial Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
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
    // A password-recovery link also completes via a full page reload on
    // web, which looks identical to a stale restart to the check below —
    // consuming this flag (set by ForgotPasswordScreen right before the
    // email was sent) lets that reload's session survive long enough for
    // ResetPasswordScreen to use it, instead of being signed straight out.
    final pendingRecovery = await SessionPrefs.consumePendingPasswordRecovery();
    final pendingOAuthChoice = await SessionPrefs.consumePendingOAuthRememberMe();
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
    if (mounted) setState(() => _checkedRememberMe = true);
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
        return const HomeScreen();
      },
    );
  }
}
