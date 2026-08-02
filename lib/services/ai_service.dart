import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared entry point for every module's AI narration feature. Calls the
/// `gemini-generate` Edge Function, which holds the Gemini key server-side —
/// the key never touches this app. `functions.invoke` attaches the logged-in
/// user's JWT automatically, which the Edge Function requires.
///
/// Callers must never send raw computed numbers expecting Gemini to do more
/// arithmetic — pass already-computed figures and ask only for a
/// plain-language explanation. See Gemini_Shared_Service_Plan.md.
class AiService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<String> generate(String prompt, {String? system}) async {
    final FunctionResponse res;
    try {
      res = await _client.functions.invoke(
        'gemini-generate',
        body: {'prompt': prompt, 'system': ?system},
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      throw Exception(message ?? 'AI service returned an error');
    }
    final data = res.data;
    if (data is! Map || data['text'] == null) {
      throw Exception('Malformed response from AI service');
    }
    return (data['text'] as String).trim();
  }
}
