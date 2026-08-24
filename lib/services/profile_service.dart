import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class ProfileService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Every profile (admin oversight only — the "read own or admin" RLS
  /// policy means a non-admin only ever gets their own row back here).
  Future<List<Profile>> getProfiles() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => Profile.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The signed-in user's own profile row, or null if there is no session
  /// (or the row hasn't been created yet — normally the handle_new_user
  /// trigger creates it at sign-up).
  Future<Profile?> getMyProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// Updates the signed-in user's own profile. Only the fields passed are
  /// written, so onboarding and the profile screen can each set the subset
  /// they collect. Backed by the "update own profile" RLS policy.
  Future<Profile> updateMyProfile({
    String? displayName,
    String? phone,
    String? jobTitle,
    String? company,
    bool? onboarded,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final updates = <String, dynamic>{
      'display_name': ?displayName,
      'phone': ?phone,
      'job_title': ?jobTitle,
      'company': ?company,
      'onboarded': ?onboarded,
    };
    final row = await _client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();
    return Profile.fromJson(row);
  }
}
