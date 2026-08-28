import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/auth_scaffold.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeAbout)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const AuthHeader(
                  icon: Icons.factory,
                  title: 'Industrial Hub',
                  subtitle: 'Industrial Hub Innovation Platform',
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'A factory capacity, stock, and supply-chain planning tool built for BMIT2073 '
                  'Mobile Application Development, in support of SDG 9 (Industry, Innovation and '
                  'Infrastructure). It compares a factory\'s own machine, manpower, and material data '
                  'against Malaysian government industrial statistics to show whether the factory can '
                  'meet demand, and what is limiting it if not.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Government data', style: textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                          'Industrial data sourced from Department of Statistics Malaysia (DOSM) via '
                          'data.gov.my, licensed under CC BY 4.0.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Datasets used: MSIC industry classification, Industrial Production Index '
                          '(IPI) by division, and labour productivity by sector.',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
