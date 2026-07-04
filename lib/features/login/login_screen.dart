import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../theme/messenger_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _twoFactorCode = TextEditingController();
  final _twoFactorFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  bool _needsTwoFactor = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _twoFactorCode.dispose();
    _twoFactorFocus.dispose();
    super.dispose();
  }

  void _backToCredentials() {
    setState(() {
      _needsTwoFactor = false;
      _twoFactorCode.clear();
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthRepository>();
    try {
      await auth.login(
        email: _email.text.trim(),
        password: _password.text,
        twoFactorCode: _needsTwoFactor ? _twoFactorCode.text.trim() : null,
      );
    } on ApiException catch (e) {
      if (e.twoFactorRequired && mounted) {
        setState(() {
          _needsTwoFactor = true;
          _error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _twoFactorFocus.requestFocus());
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext = messengerExt(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0B141A), const Color(0xFF1F2C34), const Color(0xFF103529)]
                : [const Color(0xFFE8F5E9), const Color(0xFFE3F2FD), const Color(0xFFF0F2F5)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: MessengerPalette.whatsAppGreen,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: MessengerPalette.whatsAppGreen.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: Icon(_needsTwoFactor ? Icons.shield_outlined : Icons.chat_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'ERPComplete',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    Text('Messenger', style: TextStyle(color: ext.subtext, fontSize: 16)),
                    const SizedBox(height: 32),
                    Card(
                      elevation: isDark ? 0 : 8,
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_needsTwoFactor) ...[
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Back',
                                    onPressed: _loading ? null : _backToCredentials,
                                    icon: const Icon(Icons.arrow_back),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Two-factor authentication',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enter the 6-digit code from your authenticator app for ${_email.text.trim()}',
                                style: TextStyle(color: ext.subtext, fontSize: 14, height: 1.4),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _twoFactorCode,
                                focusNode: _twoFactorFocus,
                                decoration: const InputDecoration(
                                  labelText: 'Authentication code',
                                  hintText: '000000',
                                  prefixIcon: Icon(Icons.pin_outlined),
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.oneTimeCode],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(8),
                                ],
                                onSubmitted: (_) => _loading ? null : _submit(),
                              ),
                            ] else ...[
                              Text('Sign in', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('Use your ERP workspace account', style: TextStyle(color: ext.subtext, fontSize: 14)),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _email,
                                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _password,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _loading ? null : _submit(),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: MessengerPalette.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(_error!, style: const TextStyle(color: MessengerPalette.danger, fontSize: 13)),
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _loading ? null : _submit,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: MessengerPalette.whatsAppGreen,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _loading
                                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(
                                      _needsTwoFactor ? 'Verify' : 'Continue',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
