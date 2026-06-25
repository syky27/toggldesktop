import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/redtick_logo.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'time_entries_screen.dart';

/// Responsive app shell (design §3.1): a branded sidebar on desktop (≥ 720 px)
/// and a bottom nav on mobile — one tree for phone and desktop.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _dest = <_Dest>[
    _Dest('Timer', Icons.timer_outlined, Icons.timer),
    _Dest('Calendar', Icons.calendar_today_outlined, Icons.calendar_today),
    _Dest('Settings', Icons.settings_outlined, Icons.settings),
  ];

  Widget _page(int i) => switch (i) {
        0 => const TimeEntriesScreen(),
        1 => const CalendarScreen(),
        _ => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              index: _index,
              destinations: _dest,
              onSelect: (i) => setState(() => _index = i),
            ),
            Expanded(child: _page(_index)),
          ],
        ),
      );
    }
    return Scaffold(
      body: _page(_index),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _dest)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });
  final int index;
  final List<_Dest> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final core = ref.watch(coreServiceProvider);
    final online = ref.watch(onlineStateProvider).asData?.value ?? 0;

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: t.sidebar,
        border: Border(right: BorderSide(color: t.hairline)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: const RedtickLogo(size: 30, wordmark: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _InstanceChip(
                  host: core.host.isEmpty ? 'redmine' : core.host,
                  online: online),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < destinations.length; i++)
              _NavItem(
                dest: destinations[i],
                selected: i == index,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            Divider(color: t.hairline, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary,
                    child: Text(_initials(core.userName),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(core.userName.isEmpty ? 'Account' : core.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('API key · ${core.maskedKey}',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _InstanceChip extends StatelessWidget {
  const _InstanceChip({required this.host, required this.online});
  final String host;
  final int online;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final ok = online == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5)),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: ok ? const Color(0xFF16A34A) : cs.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(ok ? 'Connected' : 'Offline',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.dest, required this.selected, required this.onTap});
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? t.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(selected ? dest.selectedIcon : dest.icon,
                    size: 19, color: color),
                const SizedBox(width: 12),
                Text(dest.label,
                    style: TextStyle(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
