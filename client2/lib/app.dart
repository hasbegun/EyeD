import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => setState(() => _extended = !_extended),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final next = locale.languageCode == 'en'
                  ? const Locale('ko')
                  : const Locale('en');
              ref.read(localeProvider.notifier).state = next;
            },
            child: Text(
              locale.languageCode == 'en' ? '한국어' : 'EN',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
