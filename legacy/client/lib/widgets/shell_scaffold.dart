import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bulk_enroll_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_mode_provider.dart';
import '../theme/eyed_theme.dart';
import 'connection_overlay.dart';
import 'nav_sidebar.dart';

class ShellScaffold extends ConsumerWidget {
  final Widget child;

  const ShellScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 20,
        title: Text(
          l10n.brandName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: cs.primary,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          _BulkEnrollChip(ref: ref, l10n: l10n),
          _StatusChip(ref: ref, l10n: l10n),
          const SizedBox(width: 8),
          _ThemeDropdown(ref: ref, l10n: l10n),
          _LocaleDropdown(ref: ref),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          const NavSidebar(),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: child,
                ),
                const Positioned.fill(
                  child: ConnectionOverlay(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- AppBar action widgets ---

class _StatusChip extends StatelessWidget {
  final WidgetRef ref;
  final AppLocalizations l10n;

  const _StatusChip({required this.ref, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final isConnected = conn.status == ConnectionStatus.connected;
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;
    final color = isConnected ? semantic.success : cs.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? l10n.statusLive : l10n.statusOffline,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ThemeDropdown extends StatelessWidget {
  final WidgetRef ref;
  final AppLocalizations l10n;

  const _ThemeDropdown({required this.ref, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;

    final icon = switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };

    return PopupMenuButton<ThemeMode>(
      tooltip: l10n.themeSystem,
      icon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      onSelected: (m) =>
          ref.read(themeModeProvider.notifier).setThemeMode(m),
      itemBuilder: (_) => [
        _themeItem(ThemeMode.system, Icons.brightness_auto, l10n.themeSystem,
            mode),
        _themeItem(
            ThemeMode.light, Icons.light_mode, l10n.themeLight, mode),
        _themeItem(
            ThemeMode.dark, Icons.dark_mode, l10n.themeDark, mode),
      ],
    );
  }

  PopupMenuEntry<ThemeMode> _themeItem(
      ThemeMode value, IconData icon, String label, ThemeMode current) {
    return PopupMenuItem<ThemeMode>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label),
          if (value == current) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16),
          ],
        ],
      ),
    );
  }
}

class _LocaleDropdown extends StatelessWidget {
  final WidgetRef ref;

  const _LocaleDropdown({required this.ref});

  static const _locales = [
    (Locale('en'), 'EN', 'English'),
    (Locale('ko'), '\ud55c', '\ud55c\uad6d\uc5b4'),
  ];

  @override
  Widget build(BuildContext context) {
    final currentLocale = ref.watch(localeProvider);
    final effective = currentLocale ?? Localizations.localeOf(context);
    final cs = Theme.of(context).colorScheme;

    final currentLabel =
        _locales.firstWhere((e) => e.$1.languageCode == effective.languageCode,
            orElse: () => _locales.first).$2;

    return PopupMenuButton<Locale>(
      tooltip: 'Language',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              currentLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
      onSelected: (locale) =>
          ref.read(localeProvider.notifier).setLocale(locale),
      itemBuilder: (_) => _locales.map((entry) {
        final selected = effective.languageCode == entry.$1.languageCode;
        return PopupMenuItem<Locale>(
          value: entry.$1,
          child: Row(
            children: [
              Text(entry.$2,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 10),
              Text(entry.$3),
              if (selected) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _BulkEnrollChip extends StatelessWidget {
  final WidgetRef ref;
  final AppLocalizations l10n;

  const _BulkEnrollChip({required this.ref, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final bulkState = ref.watch(bulkEnrollProvider);
    if (!bulkState.running) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            l10n.bulkEnrollProgress(bulkState.processed),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
