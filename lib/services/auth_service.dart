import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session_prefs.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({required String email, required String password}) async {
    await _client.auth.signUp(email: email, password: password);
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb
          ? Uri.base.origin
          : 'io.supabase.industrialhub://login-callback/',
    );
  }

  /// Sends a password-reset email. Supabase does not error when [email]
  /// isn't registered, so this stays silent either way — the caller should
  /// show the same message regardless, to avoid letting the form be used
  /// to check which emails have an account.
  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb
          ? Uri.base.origin
          : 'io.supabase.industrialhub://login-callback/',
    );
  }

  /// Sets a new password on the current session — used to finish a
  /// password-reset flow once the recovery link has signed the user in.
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await SessionPrefs.clear();
  }
}
