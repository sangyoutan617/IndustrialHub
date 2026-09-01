import 'package:shared_preferences/shared_preferences.dart';

class SessionPrefs {
  static const _rememberUntilKey = 'remember_until_millis';
  static const _oauthPendingRememberKey = 'oauth_pending_remember_me';
  static const _pendingPasswordRecoveryKey = 'pending_password_recovery';
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

  static Future<bool> shouldStayLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final untilMillis = prefs.getInt(_rememberUntilKey);
    if (untilMillis == null) return false;
    return DateTime.now().millisecondsSinceEpoch < untilMillis;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberUntilKey);
    await prefs.remove(_oauthPendingRememberKey);
    await prefs.remove(_pendingPasswordRecoveryKey);
  }

  static Future<void> markPendingOAuthRememberMe(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_oauthPendingRememberKey, remember);
  }

  static Future<bool?> consumePendingOAuthRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_oauthPendingRememberKey)) return null;
    final value = prefs.getBool(_oauthPendingRememberKey);
    await prefs.remove(_oauthPendingRememberKey);
    return value;
  }

  static Future<void> markPendingPasswordRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingPasswordRecoveryKey, true);
  }

  static Future<bool> consumePendingPasswordRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_pendingPasswordRecoveryKey) ?? false;
    await prefs.remove(_pendingPasswordRecoveryKey);
    return value;
  }
}
