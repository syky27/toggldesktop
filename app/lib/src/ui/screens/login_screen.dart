import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';

/// Redmine login: backend URL + API key (used as email/password into the core's
/// `toggl_login`). Mirrors the Qt `loginwidget`. Implements FP-41.
///
/// The backend URL is set via the core's environment/base-url configuration;
/// here we collect it and the API key. The Redmine fork accepts the API key in
/// the password field and the account email/login in the email field.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _apiKey = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _login.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final ok = ref
        .read(coreServiceProvider)
        .login(_login.text.trim(), _apiKey.text.trim());
    // The auth gate switches automatically on the on_login callback; if the
    // synchronous call already failed, re-enable the form.
    if (!ok) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 64, color: RedtickTheme.brand),
                  const SizedBox(height: 8),
                  Text('Redtick',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _login,
                    decoration: const InputDecoration(
                      labelText: 'Redmine login',
                      border: OutlineInputBorder(),
                    ),
                    autofillHints: const [AutofillHints.username],
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apiKey,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  if (_submitting)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton(
                      onPressed: _submit,
                      child: const Text('Log in'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
