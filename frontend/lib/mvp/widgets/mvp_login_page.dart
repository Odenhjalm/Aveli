import 'package:flutter/material.dart';

import '../../mvp/api_client.dart';

class MvpLoginPage extends StatefulWidget {
  const MvpLoginPage({super.key, required this.client, required this.onSuccess});

  final MvpApiClient client;
  final VoidCallback onSuccess;

  @override
  State<MvpLoginPage> createState() => _MvpLoginPageState();
}

class _MvpLoginPageState extends State<MvpLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isRegister) {
        await widget.client.register(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _displayName.text.isEmpty ? 'Aveli Teacher' : _displayName.text,
        );
      }
      await widget.client.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      widget.onSuccess();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 6,
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'AVELI Studio Login',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'E-post'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Lösenord'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isRegister
                          ? TextField(
                              key: const ValueKey('display-name'),
                              controller: _displayName,
                              decoration: const InputDecoration(labelText: 'Visningsnamn'),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegister ? 'Registrera' : 'Logga in'),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _isRegister = !_isRegister),
                      child: Text(_isRegister ? 'Jag har redan konto' : 'Skapa konto'),
                    ),
                    const SizedBox(height: 8),
                    Text('Bas-URL: ${widget.client.baseUrl}', textAlign: TextAlign.center),
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
