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

  /// Whether [email] belongs to a registered account. Goes through the
  /// `email_is_registered` RPC (a SECURITY DEFINER function) because the
  /// anon client can't query `auth.users` directly — see the migration
  /// note above that function's SQL for how to create it.
  Future<bool> isEmailRegistered(String email) async {
    final result = await _client.rpc(
      'email_is_registered',
      params: {'p_email': email},
    );
    return result as bool;
  }

  /// Sends a password-reset email. Supabase itself does not error when
  /// [email] isn't registered — callers that want to reject unregistered
  /// emails up front should check [isEmailRegistered] first.
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
