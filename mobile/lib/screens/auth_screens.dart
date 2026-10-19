import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session.dart';
import '../widgets/form_bits.dart';

// ------------------------------------------------------------------ login --

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the session changes and the app switches screens.
      await ApiService().login(cleanEmail(_email.text), _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to monitor your detectors.',
      form: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmailField(controller: _email),
              const SizedBox(height: 14),
              PasswordField(
                controller: _password,
                label: 'Password',
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ForgotPasswordScreen(initialEmail: cleanEmail(_email.text)))),
                  child: const Text('Forgot password?'),
                ),
              ),
              if (_error != null) ErrorText(_error!),
              const SizedBox(height: 14),
              BusyButton(label: 'Log in', busy: _busy, onPressed: _submit),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final existing = await Navigator.of(context).push<String>(
                                MaterialPageRoute(builder: (_) => const RegisterScreen()));
                            if (existing != null && mounted) {
                              setState(() {
                                _email.text = existing;
                                _error = null;
                              });
                            }
                          },
                    child: const Text('Create one'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- register --

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The app root switches to the verify-email screen.
      await ApiService()
          .register(_name.text.trim(), cleanEmail(_email.text), _password.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _accountExists = e.message.contains('already exists');
          _error = _accountExists
              ? 'You already have a NotiFire account with this email. Log in instead, '
                  "or reset your password if you don't remember it."
              : e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _accountExists = false;

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create account',
      subtitle: 'Set up NotiFire to protect your home.',
      showBack: true,
      form: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline)),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
              const SizedBox(height: 14),
              _EmailField(controller: _email),
              const SizedBox(height: 14),
              PasswordField(
                controller: _password,
                label: 'Password',
                autofillHints: const [AutofillHints.newPassword],
                helper: 'At least 8 characters, not only numbers',
                validator: validateNewPassword,
              ),
              const SizedBox(height: 14),
              PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
              if (_error != null) ErrorText(_error!),
              if (_accountExists)
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      // Back to Log in with the email filled in.
                      onPressed: () => Navigator.of(context).pop(cleanEmail(_email.text)),
                      child: const Text('Log in'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ForgotPasswordScreen(initialEmail: cleanEmail(_email.text)))),
                      child: const Text('Forgot password?'),
                    ),
                  ],
                ),
              const SizedBox(height: 22),
              BusyButton(label: 'Create account', busy: _busy, onPressed: _submit),
              const SizedBox(height: 10),
              Text(
                'We will email you a 6-digit code to confirm your address.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- verify email --

/// Shown after registering (and on login) until the email is verified.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  int _cooldown = 60; // the server just sent one
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the session updates and the app opens the main screen.
      await ApiService().verifyEmail(_code.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final msg = await ApiService().resendVerificationCode();
      if (!mounted) return;
      setState(() => _info = msg);
      _startCooldown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      final wait = RegExp(r'(\d+) seconds').firstMatch(e.message);
      if (wait != null) _startCooldown(int.parse(wait.group(1)!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Session.instance.user?.email ?? 'your email';
    return _AuthScaffold(
      title: 'Check your email',
      subtitle: 'We sent a 6-digit code to $email. Enter it below to finish setting up your account.',
      form: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CodeField(controller: _code, onCompleted: (_) => _verify()),
            if (_error != null) ErrorText(_error!),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_info!,
                    style: const TextStyle(color: Colors.greenAccent)),
              ),
            const SizedBox(height: 22),
            BusyButton(label: 'Verify email', busy: _busy, onPressed: _verify),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cooldown > 0 ? null : _resend,
              child: Text(_cooldown > 0
                  ? 'Resend code in ${_cooldown}s'
                  : "Didn't get it? Resend code"),
            ),
            Text(
              'Check your spam folder too. The code expires in 15 minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ApiService().logout(),
              child: const Text('Wrong email? Log out'),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------- forgot password --

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (validateEmail(_email.text) != null) {
      _form.currentState!.validate();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService().forgotPassword(cleanEmail(_email.text));
      if (mounted) setState(() => _codeSent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Logs in on success; the app root takes over.
      await ApiService()
          .resetPassword(cleanEmail(_email.text), _code.text, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Reset password',
      subtitle: _codeSent
          ? 'If an account exists for ${cleanEmail(_email.text)}, we emailed it a 6-digit code.'
          : 'Enter your account email and we will send you a code.',
      showBack: true,
      form: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EmailField(controller: _email, enabled: !_codeSent),
            if (_codeSent) ...[
              const SizedBox(height: 18),
              CodeField(controller: _code, autofocus: true),
              const SizedBox(height: 14),
              PasswordField(
                controller: _password,
                label: 'New password',
                autofillHints: const [AutofillHints.newPassword],
                helper: 'At least 8 characters, not only numbers',
                validator: validateNewPassword,
              ),
              const SizedBox(height: 14),
              PasswordField(
                controller: _confirm,
                label: 'Confirm new password',
                onSubmitted: (_) => _reset(),
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
            ],
            if (_error != null) ErrorText(_error!),
            const SizedBox(height: 22),
            _codeSent
                ? BusyButton(label: 'Set new password', busy: _busy, onPressed: _reset)
                : BusyButton(label: 'Send code', busy: _busy, onPressed: _sendCode),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : () => setState(() => _codeSent = false),
                child: const Text('Use a different email / resend'),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ shared UI --

class _AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget form;
  final bool showBack;

  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.form,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBack ? AppBar(backgroundColor: Colors.transparent) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_fire_department,
                          color: Color(0xFFFF7043), size: 40),
                      SizedBox(width: 8),
                      Text('NotiFire',
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 24),
                  form,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  const _EmailField({required this.controller, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      decoration: const InputDecoration(
          labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
      validator: validateEmail,
    );
  }
}
