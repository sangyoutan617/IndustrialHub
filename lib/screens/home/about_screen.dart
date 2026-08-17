import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final currentLang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeAbout)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.factory,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Industrial Hub',
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Industrial Hub Innovation Platform',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.translate, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Text(l10n.language, style: textTheme.titleMedium),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(l10n.languageEnglish),
                    trailing: currentLang == 'en'
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => MyApp.setLocale(context, const Locale('en')),
                  ),
                  ListTile(
                    title: Text(l10n.languageMalay),
                    trailing: currentLang == 'ms'
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => MyApp.setLocale(context, const Locale('ms')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
    );
  }
}
