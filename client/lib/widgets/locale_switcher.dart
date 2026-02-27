import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/locale_provider.dart';

class LocaleSwitcher extends ConsumerWidget {
  const LocaleSwitcher({super.key});

  static const _locales = [
    Locale('en'),
    Locale('ko'),
  ];

  static const _labels = {
    'en': 'EN',
    'ko': '\ud55c',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final effective = currentLocale ?? Localizations.localeOf(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.language, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          for (final locale in _locales) ...[
            InkWell(
              onTap: () => ref.read(localeProvider.notifier).setLocale(locale),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: effective.languageCode == locale.languageCode
                      ? cs.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: effective.languageCode == locale.languageCode
                        ? cs.primary
                        : cs.outlineVariant,
                  ),
                ),
                child: Text(
                  _labels[locale.languageCode]!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: effective.languageCode == locale.languageCode
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (locale != _locales.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
