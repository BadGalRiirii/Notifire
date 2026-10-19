import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.onSubmitted != null
          ? TextInputAction.done
          : TextInputAction.next,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// Client-side check matching the server's rules (it re-checks anyway).
String? validateNewPassword(String? v) {
  if (v == null || v.length < 8) return 'Use at least 8 characters';
  if (RegExp(r'^\d+$').hasMatch(v)) return "Password can't be only numbers";
  return null;
}

final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

// Spaces plus the invisible characters keyboards and autofill can slip in
// (zero-width space/joiners, no-break space, word joiner, BOM).
final _emailJunk = RegExp(r"[\s\u00a0\u200b-\u200d\u2060\ufeff]");

/// The email as the server should see it: no spaces or invisible
/// characters, full-width letters (some keyboards) as normal ones,
/// lowercase, and a keyboard-suggested comma read as a dot (emails can't
/// contain commas).
String cleanEmail(String v) => String.fromCharCodes(v
        .replaceAll(_emailJunk, '')
        .runes
        .map((c) => c >= 0xFF01 && c <= 0xFF5E ? c - 0xFEE0 : (c == 0xFE6B ? 0x40 : c)))
    .replaceAll(',', '.')
    .toLowerCase();

/// Says what the app actually read, so an autofilled name or a typo is
/// easy to spot.
String? validateEmail(String? v) {
  final email = cleanEmail(v ?? '');
  if (email.isEmpty) return 'Enter your email';
  if (emailPattern.hasMatch(email)) return null;
  return '"$email" is not an email address. Type it like name@gmail.com';
}

/// Large 6-digit code input.
class CodeField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  const CodeField(
      {super.key, required this.controller, this.onCompleted, this.autofocus = true});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 30, letterSpacing: 12, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(counterText: '', hintText: '••••••'),
      validator: (v) => (v == null || v.length != 6) ? 'Enter the 6-digit code' : null,
      onChanged: (v) {
        if (v.length == 6) onCompleted?.call(v);
      },
    );
  }
}

class ErrorText extends StatelessWidget {
  final String message;
  const ErrorText(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 6),
          Expanded(
              child: Text(message, style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }
}

/// Button with a spinner while [busy]. If the wait gets long, explains that
/// the server is starting up (the free server sleeps when idle).
class BusyButton extends StatefulWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const BusyButton(
      {super.key, required this.label, required this.busy, required this.onPressed});

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _startTimer();
  }

  @override
  void didUpdateWidget(BusyButton old) {
    super.didUpdateWidget(old);
    if (widget.busy && !old.busy) _startTimer();
    if (!widget.busy && old.busy) {
      _slowTimer?.cancel();
      _slow = false;
    }
  }

  void _startTimer() {
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      onPressed: widget.busy ? null : widget.onPressed,
      child: widget.busy
          ? const SizedBox(
              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Text(widget.label, style: const TextStyle(fontSize: 16)),
    );
    if (!(widget.busy && _slow)) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        const SizedBox(height: 8),
        Text('NotiFire is starting up. This can take up to a minute, please keep the app open.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
      ],
    );
  }
}
