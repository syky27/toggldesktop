import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// Settings/preferences (FP-47). Scaffolded with a logout action and online
/// status; the full settings form (mapped from the Qt `preferencesdialog`)
/// binds to `toggl_get_settings`/`toggl_set_settings_*` in FP-47.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineStateProvider).asData?.value;
    return SafeArea(
      child: ListView(
        children: [
          ListTile(
            title: const Text('Connection'),
            subtitle: Text(switch (online) {
              0 => 'Online',
              1 => 'No network',
              2 => 'Backend down',
              _ => 'Unknown',
            }),
            leading: const Icon(Icons.wifi),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () => ref.read(coreServiceProvider).logout(),
          ),
        ],
      ),
    );
  }
}
