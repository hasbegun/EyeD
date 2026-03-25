import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/mode_config.dart';
import 'l10n/app_localizations.dart';
import 'providers/fhe_provider.dart';
import 'screens/enroll_screen.dart';
import 'screens/detect_screen.dart';
import 'screens/log_screen.dart';

final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));

class EyeDApp extends ConsumerWidget {
  const EyeDApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: 'EyeD',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _Shell(),
    );
  }
}

class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _index = 0;
  bool _extended = true;

  static const _pages = <Widget>[
    EnrollScreen(),
    DetectScreen(),
    LogScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => setState(() => _extended = !_extended),
        ),
        actions: [
          if (ModeConfig.showDevTools) ...[
            const _DevBadge(),
            const SizedBox(width: 8),
            const _FheToggle(),
            const SizedBox(width: 8),
          ],
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: locale.languageCode,
              isDense: true,
              borderRadius: BorderRadius.circular(8),
              dropdownColor: theme.colorScheme.surface,
              iconEnabledColor: theme.colorScheme.onSurface,
              style: TextStyle(color: theme.colorScheme.onSurface),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('EN')),
                DropdownMenuItem(value: 'ko', child: Text('KO')),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref.read(localeProvider.notifier).state = Locale(value);
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: _extended,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: const SizedBox(height: 8),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.person_add_outlined),
                selectedIcon: const Icon(Icons.person_add),
                label: Text(l.enrollPage),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search_outlined),
                selectedIcon: const Icon(Icons.search),
                label: Text(l.detectPage),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.history_outlined),
                selectedIcon: const Icon(Icons.history),
                label: Text(l.logPage),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _pages[_index]),
        ],
      ),
    );
  }
}

/// Amber mode badge (DEV/TEST) in the AppBar — compiled in only when
/// [ModeConfig.showDevTools] is true (const-guarded, tree-shaken in prod).
class _DevBadge extends StatelessWidget {
  const _DevBadge();

  @override
  Widget build(BuildContext context) {
    final modeLabel = ModeConfig.mode.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.shade600,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        modeLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// FHE toggle chip — only rendered in dev/test builds
/// (behind [ModeConfig.showDevTools]).
/// Shows the current FHE state and allows toggling via [fheProvider].
class _FheToggle extends ConsumerWidget {
  const _FheToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final fheAsync = ref.watch(fheProvider);

    return fheAsync.when(
      loading: () => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (state) {
        if (state.isToggling) {
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return ActionChip(
          avatar: Icon(
            state.fheEnabled ? Icons.lock : Icons.lock_open,
            size: 16,
            color: state.fheEnabled
                ? Colors.green.shade700
                : Colors.orange.shade700,
          ),
          label: Text(
            state.fheEnabled ? l.fheOn : l.fheOff,
            style: TextStyle(
              fontSize: 13,
              color: state.fheEnabled
                  ? Colors.green.shade800
                  : Colors.orange.shade800,
            ),
          ),
          backgroundColor: state.fheEnabled
              ? Colors.green.shade50
              : Colors.orange.shade50,
          side: BorderSide(
            color: state.fheEnabled
                ? Colors.green.shade300
                : Colors.orange.shade300,
          ),
          onPressed: () async {
            try {
              await ref
                  .read(fheProvider.notifier)
                  .toggle(!state.fheEnabled);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.fheToggleError)),
                );
              }
            }
          },
        );
      },
    );
  }
}
