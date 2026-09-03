import 'package:flutter/material.dart';
import '../models/msic_code.dart';

class MsicField extends StatelessWidget {
  final List<MsicCode> codes;
  final String? selectedCode;
  final ValueChanged<String?> onChanged;
  final String labelText;

  const MsicField({
    super.key,
    required this.codes,
    required this.selectedCode,
    required this.onChanged,
    this.labelText = 'Industry (MSIC)',
  });

  MsicCode? get _selected {
    final code = selectedCode;
    if (code == null) return null;
    final matches = codes.where((c) => c.msicCode == code);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await Navigator.of(context).push<MsicCode>(
      MaterialPageRoute(builder: (_) => _MsicSearchScreen(codes: codes)),
    );
    if (picked != null) onChanged(picked.msicCode);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: codes.isEmpty ? null : () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          suffixIcon: const Icon(Icons.search),
        ),
        child: Text(
          selected?.description ??
              (codes.isEmpty ? 'Loading…' : 'Select an industry'),
          style: selected == null
              ? TextStyle(color: scheme.onSurfaceVariant)
              : null,
        ),
      ),
    );
  }
}

class _MsicSearchScreen extends StatefulWidget {
  final List<MsicCode> codes;

  const _MsicSearchScreen({required this.codes});

  @override
  State<_MsicSearchScreen> createState() => _MsicSearchScreenState();
}

class _MsicSearchScreenState extends State<_MsicSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<MsicCode> get _filtered {
    if (_query.trim().isEmpty) return widget.codes;
    final q = _query.trim().toLowerCase();
    return widget.codes
        .where(
          (c) =>
              c.description.toLowerCase().contains(q) ||
              c.msicCode.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search industry or MSIC code',
            border: InputBorder.none,
          ),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white),
          cursorColor: Colors.white,
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('No matching industries'))
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final code = filtered[index];
                return ListTile(
                  title: Text(code.description),
                  subtitle: Text('MSIC ${code.msicCode}'),
                  onTap: () => Navigator.pop(context, code),
                );
              },
            ),
    );
  }
}
