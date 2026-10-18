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

String? validateEmail(String? v) =>
    (v == null || !emailPattern.hasMatch(v.trim())) ? 'Enter a valid email' : null;

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

class BusyButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const BusyButton(
      {super.key, required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Text(label, style: const TextStyle(fontSize: 16)),
    );
  }
}
