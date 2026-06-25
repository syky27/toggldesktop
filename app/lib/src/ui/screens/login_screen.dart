import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/redtick_logo.dart';

/// Redmine login (design "Login — desktop/mobile"): backend **URL** + **API
/// key**. Desktop ≥ 720 px shows the split brand panel; narrower is a centered
/// column. The URL is applied via `setBaseUrl` first; the API key is the only
/// credential. Login is async — the auth gate flips on the `on_login` stream and
/// errors surface inline (the UI isolate is never blocked).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _apiKey = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final core = ref.read(coreServiceProvider);
    core.setBaseUrl(_host.text.trim());
    core.login('', _apiKey.text.trim());
    // Success: on_login flips the auth gate (this screen is disposed).
    // Failure: the errorsProvider listener re-enables the form below.
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(errorsProvider, (_, next) {
      final err = next.asData?.value;
      if (_submitting && err != null && err.message.isNotEmpty) {
        setState(() {
          _submitting = false;
          _error = err.message;
        });
      }
    });

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          if (!wide) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        const RedtickLogo(size: 72),
                        const SizedBox(height: 16),
                        Text('Redtick',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Redmine-native time tracking',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(height: 32),
                        _form(context),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: _brandPanel(context)),
              Expanded(
                flex: 6,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Connect to Redmine',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text('Point Redtick at your instance to start tracking.',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(height: 28),
                          _form(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _brandPanel(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB5231F), kBrandRed, Color(0xFF7E1411)],
        ),
      ),
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RedtickLogo(size: 40, wordmark: true, wordmarkColor: Colors.white),
          const Spacer(),
          const Text('Your timer,\nyour Redmine.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          const Text(
            'Track straight into the Redmine instance you already run. '
            'No Toggl account, no third-party cloud.',
            style: TextStyle(color: Color(0xCCFFFFFF), height: 1.5),
          ),
          const Spacer(flex: 2),
          _tick('Personal API key — no passwords'),
          _tick('Issues & projects load live'),
          _tick('Entries stay on your server'),
        ],
      ),
    );
  }

  Widget _tick(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );

  Widget _form(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: 'Redmine URL',
            controller: _host,
            enabled: !_submitting,
            icon: Icons.public,
            hint: 'https://redmine.example.com',
            keyboardType: TextInputType.url,
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'API access key',
            controller: _apiKey,
            enabled: !_submitting,
            icon: Icons.key_outlined,
            obscure: _obscure,
            hint: 'Paste your key',
            onSubmitted: (_) => _submit(),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            trailing: IconButton(
              icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 8),
          Text('Redmine → My account → API access key',
              style: TextStyle(color: muted, fontSize: 12)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt, size: 18),
              label: Text(_submitting ? 'Connecting…' : 'Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled, filled input matching the design's `.input` style.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.enabled = true,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.onSubmitted,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: muted),
            suffixIcon: trailing,
            hintText: hint,
          ),
        ),
      ],
    );
  }
}
