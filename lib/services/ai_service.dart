import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
  final SupabaseClient _client = Supabase.instance.client;

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
      }
    }
    throw Exception('AI service returned an error');
  }
}
