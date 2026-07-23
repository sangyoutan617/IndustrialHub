import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the current login should survive an app restart, and for
/// how long. Supabase itself always persists the session locally — this is
/// a separate, app-level "remember me" boundary layered on top of that: if
/// the box wasn't checked at login, [shouldStayLoggedIn] reports false on
/// the next cold start even though a valid Supabase session still exists.
class SessionPrefs {
  static const _rememberUntilKey = 'remember_until_millis';
  static const _oauthPendingRememberKey = 'oauth_pending_remember_me';
  static const _rememberDuration = Duration(days: 30);

  static Future<void> setRememberMe(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    if (remember) {
      final until = DateTime.now().add(_rememberDuration);
      await prefs.setInt(_rememberUntilKey, until.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_rememberUntilKey);
    }
  }

  /// Whether a previously started session is still within its remembered
  /// window. False if "remember me" was never checked, or the 30 days ran out.
  static Future<bool> shouldStayLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final untilMillis = prefs.getInt(_rememberUntilKey);
    if (untilMillis == null) return false;
    return DateTime.now().millisecondsSinceEpoch < untilMillis;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberUntilKey);
  }

  /// Web OAuth completes via a full page reload, which looks identical to a
  /// genuine app restart to [shouldStayLoggedIn]. Stash the checkbox choice
  /// here right before redirecting so the reload that finishes the sign-in
  /// can apply it, instead of the restart check treating a brand-new login
  /// as a stale session and immediately signing it back out.
  static Future<void> markPendingOAuthRememberMe(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_oauthPendingRememberKey, remember);
  }

  /// Reads and clears the pending choice from [markPendingOAuthRememberMe].
  /// Returns null when this cold start wasn't the result of an OAuth
  /// redirect (e.g. a normal app restart).
  static Future<bool?> consumePendingOAuthRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_oauthPendingRememberKey)) return null;
    final value = prefs.getBool(_oauthPendingRememberKey);
    await prefs.remove(_oauthPendingRememberKey);
    return value;
  }
}
