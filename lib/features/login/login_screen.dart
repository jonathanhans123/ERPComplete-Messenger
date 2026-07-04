import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../core/auth/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _apiUrl = TextEditingController(text: ApiConfig.defaultBaseUrl);
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthRepository>();
    _apiUrl.text = auth.apiBaseUrl;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _apiUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthRepository>();
    try {
      await auth.saveApiBaseUrl(_apiUrl.text);
      await auth.login(email: _email.text.trim(), password: _password.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ERPComplete Messenger')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Sign in to your workspace',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _apiUrl,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
