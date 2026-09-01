import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/ai_service.dart';

enum _AiState { idle, loading, ready, unavailable }

class AiInsightCard extends StatefulWidget {
  final String Function() buildPrompt;
  final String? system;

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
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    switch (_state) {
      case _AiState.idle:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary),
                const SizedBox(width: AppSpacing.m),
                Expanded(child: Text(l10n.aiGetExplanation)),
                FilledButton(
                  onPressed: _loadCachedOrGenerate,
                  child: Text(l10n.aiGenerateInsight),
                ),
              ],
            ),
          ),
        );
      case _AiState.loading:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.m),
                Text(l10n.aiGenerating),
              ],
            ),
          ),
        );
      case _AiState.ready:
        return Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        l10n.aiGenerated,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      color: scheme.onPrimaryContainer,
                      tooltip: 'Regenerate',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _generate,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  _text ?? '',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
        );
      case _AiState.unavailable:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            l10n.aiUnavailable,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
    }
  }
}
