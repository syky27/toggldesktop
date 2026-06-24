import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

/// Root widget. Routes between the login screen and the main shell based on the
/// core's login state, and wires global error toasts. Implements FP-40 (shell).
class RedtickApp extends ConsumerWidget {
  const RedtickApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Redtick',
      debugShowCheckedModeBanner: false,
      theme: RedtickTheme.light(),
      darkTheme: RedtickTheme.dark(),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface core errors as snackbars globally.
    ref.listen(errorsProvider, (_, next) {
      final err = next.asData?.value;
      if (err != null && err.message.isNotEmpty) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(SnackBar(content: Text(err.message)));
      }
    });

    final loggedIn = ref.watch(isLoggedInProvider);
    return loggedIn ? const HomeShell() : const LoginScreen();
  }
}
