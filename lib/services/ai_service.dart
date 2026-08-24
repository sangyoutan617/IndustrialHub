import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared entry point for every module's AI narration feature. Calls the
/// `gemini-generate` Edge Function, which holds the Gemini key server-side —
/// the key never touches this app. `functions.invoke` attaches the logged-in
/// user's JWT automatically, which the Edge Function requires.
///
/// Callers must never send raw computed numbers expecting Gemini to do more
/// arithmetic — pass already-computed figures and ask only for a
/// plain-language explanation. See the "Shared AI service" section of the
/// README for the full design.
class AiService {
  final SupabaseClient _client = Supabase.instance.client;

  // Gemini's free tier rate-limits requests per minute; a burst of AI cards
  // loading close together (e.g. flicking through tabs) trips it and the
  // Edge Function relays that as a 502. Live project logs showed these
  // clearing within seconds, so a couple of short-backoff retries turn most
  // of them into a slightly slower success instead of "AI insight
  // unavailable". Anything that isn't a 502 (bad request, missing key,
  // unauthorized) won't succeed on retry, so those fail immediately.
  static const _maxAttempts = 3;

  Future<String> generate(String prompt, {String? system}) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (attempt > 1) {
        await Future.delayed(Duration(milliseconds: 800 * (attempt - 1)));
      }
      try {
        final res = await _client.functions.invoke(
          'gemini-generate',
          body: {'prompt': prompt, 'system': ?system},
        );
        final data = res.data;
        if (data is! Map || data['text'] == null) {
          throw Exception('Malformed response from AI service');
        }
        return (data['text'] as String).trim();
      } on FunctionException catch (e) {
        final isRateLimit = e.status == 502;
        if (!isRateLimit || attempt == _maxAttempts) {
          final details = e.details;
          final message = details is Map ? details['error'] : null;
          throw Exception(message ?? 'AI service returned an error');
        }
        // Otherwise fall through and retry.
      }
    }
    // Unreachable — the loop always returns or throws — but required for
    // the function's return type.
    throw Exception('AI service returned an error');
  }
}
