import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/redtick_logo.dart';
import 'calendar_screen.dart';
import 'reports_screen.dart';
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
    _Dest('Reports', Icons.bar_chart_outlined, Icons.bar_chart),
    _Dest('Settings', Icons.settings_outlined, Icons.settings),
  ];

  Widget _page(int i) => switch (i) {
        0 => const TimeEntriesScreen(),
        1 => const CalendarScreen(),
        2 => const ReportsScreen(),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _InstanceChip(),
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

/// The sidebar connection chip (desktop): host + "Synced · Ns ago" status and a
/// manual refresh button (desktop has no pull-to-refresh). Design comp §3.1.
class _InstanceChip extends ConsumerStatefulWidget {
  const _InstanceChip();

  @override
  ConsumerState<_InstanceChip> createState() => _InstanceChipState();
}

class _InstanceChipState extends ConsumerState<_InstanceChip> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(coreServiceProvider).refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final core = ref.watch(coreServiceProvider);
    final online = ref.watch(onlineStateProvider).asData?.value ?? 0;
    final lastSync = ref.watch(syncStateProvider).asData?.value;
    final ok = online == 0;
    final host = core.host.isEmpty ? 'redmine' : core.host;
    final status = ok ? 'Synced · ${_ago(lastSync)}' : 'Offline';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 9, 9),
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
                    Text(status,
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Refresh',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _busy ? null : _refresh,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.hairline),
                  ),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.refresh, size: 17, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Short relative time for the sync chip ("just now" / "Ns ago" / …).
String _ago(DateTime? t) {
  if (t == null) return 'just now';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
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
