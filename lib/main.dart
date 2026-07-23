import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/session_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
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

  @override
  void initState() {
    super.initState();
    _enforceRememberMeWindow();
  }

  // "Remember me" is an app-level boundary on top of Supabase's own session
  // persistence: if the box wasn't checked at login (or the 30 days are up),
  // sign out on this cold start even though a valid session still exists.
  //
  // Web OAuth (Google) redirects away and back, which reloads the whole app
  // and lands here immediately after a login the user just completed — that
  // one cold start must not undo it, regardless of the remember-me choice,
  // the same way a same-page email/password login is never touched by this
  // check until some later cold start. See SessionPrefs.markOAuthLoginPending.
  Future<void> _enforceRememberMeWindow() async {
    if (_initialSession != null) {
      final oauthJustCompleted = await SessionPrefs.consumeOAuthLoginPending();
      if (!oauthJustCompleted) {
        final stayLoggedIn = await SessionPrefs.shouldStayLoggedIn();
        if (!stayLoggedIn) {
          await Supabase.instance.client.auth.signOut();
        }
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
        return session != null ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
