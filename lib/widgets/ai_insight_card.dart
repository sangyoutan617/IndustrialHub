import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/ai_service.dart';

enum _AiState { idle, loading, ready, unavailable }

/// Shared "AI insight" card every module reuses to narrate its own
/// already-computed figures. The card never computes anything itself — it
/// just sends [buildPrompt]'s output to Gemini and shows the reply.
///
/// On failure it degrades quietly (a small "AI insight unavailable" line,
/// never an error dialog) — the screen's real data is already visible above
/// it and must keep working regardless of AI availability.
class AiInsightCard extends StatefulWidget {
  final String Function() buildPrompt;
  final String? system;

  /// If true, the card calls Gemini as soon as it's built. If false, it
  /// shows a "Generate insight" button and waits for a tap.
  final bool autoLoad;

  const AiInsightCard({
    super.key,
    required this.buildPrompt,
    this.system,
    this.autoLoad = true,
  });

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  // Process-lifetime cache, keyed by the exact prompt text. Screens that
  // push/pop routes (e.g. dashboard -> machine list -> back) or switch tabs
  // recreate this widget's State from scratch, which would otherwise mean
  // re-calling Gemini every time the user merely navigates away and back.
  // Keying on the prompt means an unchanged prompt reuses the cached answer;
  // a prompt that changed (because the underlying numbers changed) still
  // fetches fresh. Cleared only on app restart — that's fine, it's a
  // convenience cache, not a correctness requirement.
  static final Map<String, String> _cache = {};

  final _aiService = AiService();
  _AiState _state = _AiState.idle;
  String? _text;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      (() async {
        await _loadCachedOrGenerate();
      })();
    }
  }

  Future<void> _loadCachedOrGenerate() async {
    final cached = _cache[widget.buildPrompt()];
    if (cached != null) {
      setState(() {
        _text = cached;
        _state = _AiState.ready;
      });
      return;
    }
    await _generate();
  }

  /// Always calls Gemini, bypassing any cached answer — used by the
  /// "Generate insight" button's first tap and the ready-state's explicit
  /// regenerate action.
  Future<void> _generate() async {
    setState(() => _state = _AiState.loading);
    final prompt = widget.buildPrompt();
    try {
      final text = await _aiService.generate(prompt, system: widget.system);
      if (!mounted) return;
      _cache[prompt] = text;
      setState(() {
        _text = text;
        _state = _AiState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _AiState.unavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AiState.idle:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.primary),
                const SizedBox(width: AppSpacing.m),
                const Expanded(child: Text('Get an AI-generated explanation')),
                FilledButton(
                  onPressed: _loadCachedOrGenerate,
                  child: const Text('Generate insight'),
                ),
              ],
            ),
          ),
        );
      case _AiState.loading:
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.m),
                Text('Generating insight…'),
              ],
            ),
          ),
        );
      case _AiState.ready:
        return Card(
          color: AppColors.primaryLight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        'AI-generated',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      color: AppColors.primaryDark,
                      tooltip: 'Regenerate',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _generate,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                Text(_text ?? ''),
              ],
            ),
          ),
        );
      case _AiState.unavailable:
        // Quiet failure — the screen's real (deterministic) data is already
        // shown elsewhere on the page, so this never blocks anything.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'AI insight unavailable',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
        );
    }
  }
}
