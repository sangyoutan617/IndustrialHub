import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/ai_service.dart';

enum _AiState { idle, loading, ready, unavailable }

class AiInsightCard extends StatefulWidget {
  final String Function() buildPrompt;
  final String? system;

  final String cacheKey;

  final bool autoLoad;

  const AiInsightCard({
    super.key,
    required this.buildPrompt,
    required this.cacheKey,
    this.system,
    this.autoLoad = false,
  });

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  static final Map<String, String> _cache = {};

  final _aiService = AiService();
  _AiState _state = _AiState.idle;
  String? _text;
  bool _restored = false;

  String get _prefsKey => 'ai_insight.${widget.cacheKey}';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var stored = _cache[widget.cacheKey];
    if (stored == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        stored = prefs.getString(_prefsKey);
      } catch (_) {}
    }
    if (!mounted) return;
    if (stored != null) {
      _cache[widget.cacheKey] = stored;
      setState(() {
        _text = stored;
        _state = _AiState.ready;
        _restored = true;
      });
      return;
    }
    setState(() => _restored = true);
    if (widget.autoLoad) await _generate();
  }

  Future<void> _generate() async {
    setState(() => _state = _AiState.loading);
    try {
      final text = await _aiService.generate(
        widget.buildPrompt(),
        system: widget.system,
      );
      if (!mounted) return;
      _cache[widget.cacheKey] = text;
      setState(() {
        _text = text;
        _state = _AiState.ready;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, text);
      } catch (_) {}
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
        if (!_restored) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary),
                const SizedBox(width: AppSpacing.m),
                Expanded(child: Text(l10n.aiGetExplanation)),
                FilledButton(
                  onPressed: _generate,
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
