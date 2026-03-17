import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/theme_mode_provider.dart';

class ThemeModeSwitcher extends ConsumerWidget {
  const ThemeModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final entry in [
            (ThemeMode.system, Icons.brightness_auto, l10n.themeSystem),
            (ThemeMode.light, Icons.light_mode, l10n.themeLight),
            (ThemeMode.dark, Icons.dark_mode, l10n.themeDark),
          ]) ...[
            Tooltip(
              message: entry.$3,
              child: InkWell(
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(entry.$1),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: mode == entry.$1
                        ? cs.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: mode == entry.$1
                          ? cs.primary
                          : cs.outlineVariant,
                    ),
                  ),
                  child: Icon(
                    entry.$2,
                    size: 14,
                    color: mode == entry.$1
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (entry.$1 != ThemeMode.dark) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
