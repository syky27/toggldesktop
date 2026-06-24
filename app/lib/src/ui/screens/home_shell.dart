import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'time_entries_screen.dart';

/// Responsive app shell (FP-40): a `NavigationBar` on compact (mobile) widths
/// and a `NavigationRail` on expanded (desktop/tablet) widths — one widget tree
/// serving phone and desktop.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = <_Dest>[
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
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
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
          for (final d in _destinations)
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

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
