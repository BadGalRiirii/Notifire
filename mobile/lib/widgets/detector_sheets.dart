import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// Bottom sheet to create a detector, or edit one when [detector] is given.
/// Returns the saved [Detector], or null if cancelled.
Future<Detector?> showDetectorFormSheet(BuildContext context,
    {Detector? detector}) {
  return showModalBottomSheet<Detector>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DetectorForm(detector: detector),
  );
}

class _DetectorForm extends StatefulWidget {
  final Detector? detector;
  const _DetectorForm({this.detector});

  @override
  State<_DetectorForm> createState() => _DetectorFormState();
}

class _DetectorFormState extends State<_DetectorForm> {
  final _form = GlobalKey<FormState>();
  late final _room = TextEditingController(text: widget.detector?.room);
  late final _name = TextEditingController(text: widget.detector?.name);
  bool _busy = false;
  String? _error;

  static const _rooms = [
    'Bedroom',
    'Living room',
    'Kitchen',
    'Dining room',
    'Garage',
  ];

  @override
  void dispose() {
    _room.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final d = widget.detector;
      final saved = d == null
          ? await api.createDetector(_room.text.trim(), _name.text.trim())
          : await api.updateDetector(d.id,
              room: _room.text.trim(), name: _name.text.trim());
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.detector != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(editing ? 'Edit detector' : 'Add a detector',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _room,
                autofocus: !editing,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Room',
                  hintText: 'e.g. Bedroom',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Which room is this detector in?'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in _rooms)
                    ChoiceChip(
                      label: Text(r),
                      selected: _room.text == r,
                      onSelected: (_) => setState(() => _room.text = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Detector name (optional)',
                  hintText: 'e.g. Smoke Alarm 1',
                  helperText: editing
                      ? null
                      : 'Leave blank to call it "${_room.text.trim().isEmpty ? 'Room' : _room.text.trim()} Detector"',
                  prefixIcon: const Icon(Icons.sensors),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(editing ? 'Save' : 'Next: connect device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
