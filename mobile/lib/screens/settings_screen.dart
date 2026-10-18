import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/session.dart';
import '../widgets/form_bits.dart';

/// Account, notification and app settings (bottom-nav tab).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  bool? _systemAllowed; // Android notification permission for NotiFire
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android settings → re-check the permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _refresh() async {
    _checkPermission();
    try {
      await _api.fetchMe();
    } on ApiException {
      // keep showing the stored copy
    }
  }

  Future<void> _checkPermission() async {
    final allowed = await PushService.instance.permissionGranted();
    if (mounted) setState(() => _systemAllowed = allowed);
  }

  Future<void> _enableNotifications() async {
    final ok = await PushService.instance.syncToken();
    if (!mounted) return;
    if (!ok) {
      // Denied before: Android only lets the user change it in settings.
      await openAppSettings();
    }
    _checkPermission();
  }

  Future<void> _toggle({bool? danger, bool? warning, bool? offline}) async {
    setState(() => _saving = true);
    try {
      await _api.updateMe(
          notifyDanger: danger, notifyWarning: warning, notifyOffline: offline);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editName(AppUser user) async {
    final controller = TextEditingController(text: user.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || name.trim() == user.name) return;
    try {
      await _api.updateMe(name: name.trim());
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'Your detectors keep running, but this phone stops receiving their alerts until you log in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    final push = PushService.instance;
    await _api.logout(pushToken: push.token);
    await push.clearToken();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final user = Session.instance.user;
        if (user == null) return const SizedBox.shrink();
        final push = PushService.instance;
        final muted = Colors.white.withValues(alpha: 0.6);

        return SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // ---------------------------------------------- account --
                const _Header('Account'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Name'),
                        subtitle: Text(user.name),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => _editName(user),
                      ),
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Email'),
                        subtitle: Text(user.email),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(const ChangeEmailScreen()),
                      ),
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Change password'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(const ChangePasswordScreen()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---------------------------------------- notifications --
                const _Header('Notifications'),
                if (!push.available)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_off_outlined),
                      title: const Text('Notifications unavailable'),
                      subtitle: Text(
                          'This version of the app was built without notification support.',
                          style: TextStyle(color: muted)),
                    ),
                  )
                else if (_systemAllowed == false)
                  Card(
                    color: Colors.orange.withValues(alpha: 0.15),
                    child: ListTile(
                      leading: const Icon(Icons.notifications_off, color: Colors.orange),
                      title: const Text('Notifications are turned off'),
                      subtitle: const Text(
                          'You will not be alerted about fire or gas until you allow notifications.'),
                      trailing: FilledButton(
                          onPressed: _enableNotifications, child: const Text('Turn on')),
                    ),
                  ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.local_fire_department,
                            color: Color(0xFFE53935)),
                        title: const Text('Danger alerts'),
                        subtitle: Text('Smoke, gas or heat at dangerous levels',
                            style: TextStyle(color: muted)),
                        value: user.notifyDanger,
                        onChanged: _saving ? null : (v) => _confirmDanger(v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFFFB300)),
                        title: const Text('Warning alerts'),
                        subtitle: Text('Readings rising above normal (can be frequent when humid)',
                            style: TextStyle(color: muted)),
                        value: user.notifyWarning,
                        onChanged: _saving ? null : (v) => _toggle(warning: v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.sensors_off, color: Colors.grey),
                        title: const Text('Offline alerts'),
                        subtitle: Text('A detector loses power or Wi-Fi',
                            style: TextStyle(color: muted)),
                        value: user.notifyOffline,
                        onChanged: _saving ? null : (v) => _toggle(offline: v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ------------------------------------------------ about --
                const _Header('About'),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.local_fire_department, color: Color(0xFFFF7043)),
                        title: Text('NotiFire'),
                        subtitle: Text(
                            'Solar-Powered IoT Fire Detection • Cagayan de Oro City'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Server'),
                        subtitle: Text(AppConfig.baseUrl, style: TextStyle(color: muted)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: () => _open(const DeleteAccountScreen()),
                  child: const Text('Delete account'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDanger(bool value) async {
    if (value) return _toggle(danger: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('Turn off danger alerts?'),
        content: const Text(
            'You will NOT be notified if a detector senses fire, smoke or gas. The detector\'s own buzzer still sounds.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep on')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn off')),
        ],
      ),
    );
    if (ok == true) _toggle(danger: false);
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55))),
      );
}

// ---------------------------------------------------------- change email --

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeSent) {
        await ApiService().requestEmailChange(_password.text, _email.text.trim());
        if (mounted) setState(() => _codeSent = true);
      } else {
        await ApiService().confirmEmailChange(_code.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Email changed to ${_email.text.trim()}')));
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SubScreen(
      title: 'Change email',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Current email: ${Session.instance.user?.email ?? ''}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'New email', prefixIcon: Icon(Icons.email_outlined)),
              validator: validateEmail,
            ),
            if (!_codeSent) ...[
              const SizedBox(height: 14),
              PasswordField(
                controller: _password,
                label: 'Your password',
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
            ] else ...[
              const SizedBox(height: 16),
              Text('Enter the 6-digit code we sent to ${_email.text.trim()}.'),
              const SizedBox(height: 10),
              CodeField(controller: _code, onCompleted: (_) => _submit()),
            ],
            if (_error != null) ErrorText(_error!),
            const SizedBox(height: 22),
            BusyButton(
                label: _codeSent ? 'Confirm new email' : 'Send code',
                busy: _busy,
                onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- change password --

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
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
      await ApiService().changePassword(_current.text, _new.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password changed. Other phones have been logged out.')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SubScreen(
      title: 'Change password',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _current,
              label: 'Current password',
              autofillHints: const [AutofillHints.password],
              autofocus: true,
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _new,
              label: 'New password',
              autofillHints: const [AutofillHints.newPassword],
              helper: 'At least 8 characters, not only numbers',
              validator: validateNewPassword,
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              onSubmitted: (_) => _submit(),
              validator: (v) => v != _new.text ? 'Passwords do not match' : null,
            ),
            if (_error != null) ErrorText(_error!),
            const SizedBox(height: 22),
            BusyButton(label: 'Change password', busy: _busy, onPressed: _submit),
            const SizedBox(height: 10),
            Text('For your security, other phones signed in to this account will be logged out.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55))),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------- delete account --

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService().deleteAccount(_password.text);
      await PushService.instance.clearToken();
      // Session cleared → the app returns to the login screen.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SubScreen(
      title: 'Delete account',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'This permanently deletes your account, all your detectors, their readings and history. Your devices will stop being accepted. This cannot be undone.',
            ),
            const SizedBox(height: 18),
            PasswordField(
              controller: _password,
              label: 'Enter your password to confirm',
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _delete(),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            if (_error != null) ErrorText(_error!),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _delete,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Delete my account permanently'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const _SubScreen({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}
