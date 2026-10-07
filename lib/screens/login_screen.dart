import 'package:flutter/material.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import 'home_screen.dart';

/// Password sign-in against any Matrix homeserver.
///
/// The homeserver field is prefilled from the previous attempt so returning
/// users only retype credentials, and a full `@alice:example.org` identifier
/// overrides it entirely.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = MatrixService.instance;

  late final TextEditingController _serverController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: MatrixService.defaultHomeserver);
    _prefillServer();
  }

  Future<void> _prefillServer() async {
    final saved = await MatrixService.lastHomeserver();
    if (mounted) _serverController.text = saved;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _message = null;
    });

    final ok = await _service.login(
      homeserver: _serverController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _message = ok ? null : _service.error;
    });
    _service.clearError();

    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WaPalette.surface,
      appBar: AppBar(title: const Text('Connexion')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: WaPalette.primary,
                    child: Text(
                      'L',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _serverController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Serveur Matrix',
                    hintText: 'https://matrix.org',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Indiquez votre serveur.'
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  enabled: !_submitting,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Identifiant',
                    hintText: 'alice ou @alice:example.org',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Indiquez votre identifiant.'
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_submitting,
                  obscureText: _obscure,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty)
                          ? 'Indiquez votre mot de passe.'
                          : null,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFD33B3B),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _message!,
                            style: const TextStyle(
                              color: Color(0xFFB3261E),
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Se connecter'),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Liber ne crée pas de comptes : inscrivez-vous d'abord sur "
                  "votre serveur (par exemple element.io), puis connectez-vous "
                  'ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: WaPalette.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
