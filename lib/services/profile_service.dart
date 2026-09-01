import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class ProfileService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Profile>> getProfiles() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => Profile.fromJson(row as Map<String, dynamic>))
        .toList();
  }

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
