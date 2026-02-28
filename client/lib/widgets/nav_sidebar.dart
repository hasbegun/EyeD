import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Whether the sidebar is collapsed (icons only) or expanded (icons + labels).
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

const double sidebarExpandedWidth = 200;
const double sidebarCollapsedWidth = 56;
const Duration _animDuration = Duration(milliseconds: 200);

class _NavItem {
  final String path;
  final String label;
  final IconData icon;

  const _NavItem(this.path, this.label, this.icon);
}

class NavSidebar extends ConsumerWidget {
  const NavSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final currentPath = GoRouterState.of(context).uri.path;
    final cs = Theme.of(context).colorScheme;

    final navItems = [
      _NavItem('/dashboard', l10n.dashboard, Icons.dashboard_outlined),
      _NavItem('/devices', l10n.devices, Icons.videocam_outlined),
      _NavItem('/enrollment', l10n.enrollment, Icons.person_add_outlined),
      _NavItem('/analysis', l10n.analysis, Icons.play_circle_outlined),
      _NavItem('/db-inspector', l10n.dbInspector, Icons.storage_outlined),
      _NavItem('/history', l10n.history, Icons.history_outlined),
      _NavItem('/admin', l10n.admin, Icons.settings_outlined),
    ];

    return AnimatedContainer(
      duration: _animDuration,
      curve: Curves.easeInOut,
      width: collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: navItems.map((item) {
                final isActive = currentPath == item.path;
                return _NavTile(
                  item: item,
                  isActive: isActive,
                  collapsed: collapsed,
                  onTap: () => context.go(item.path),
                );
              }).toList(),
            ),
          ),
          // Collapse toggle at the bottom
          Divider(height: 1, color: cs.outlineVariant),
          _CollapseToggle(collapsed: collapsed, ref: ref),
        ],
      ),
    );
  }
}

class _CollapseToggle extends StatelessWidget {
  final bool collapsed;
  final WidgetRef ref;

  const _CollapseToggle({required this.collapsed, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => ref.read(sidebarCollapsedProvider.notifier).state =
          !collapsed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Icon(
          collapsed ? Icons.chevron_right : Icons.chevron_left,
          size: 20,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.isActive,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isActive ? cs.primary : cs.onSurfaceVariant;

    final tile = Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isActive ? cs.primary : Colors.transparent,
            width: 3,
          ),
        ),
        color: isActive ? cs.surfaceContainerHighest : Colors.transparent,
      ),
      child: InkWell(
        onTap: onTap,
        hoverColor: cs.surfaceContainerHighest,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 20,
            vertical: 10,
          ),
          child: collapsed
              ? Center(child: Icon(item.icon, size: 20, color: iconColor))
              : Row(
                  children: [
                    Icon(item.icon, size: 18, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: isActive
                              ? cs.primary
                              : cs.onSurfaceVariant,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    if (collapsed) {
      return Tooltip(message: item.label, child: tile);
    }
    return tile;
  }
}
