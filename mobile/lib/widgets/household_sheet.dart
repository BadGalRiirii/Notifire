import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'form_bits.dart';

/// Who gets a detector's alerts. The owner adds people in the household by
/// email and can remove them; members see the list.
Future<void> showHouseholdSheet(BuildContext context, Detector detector) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HouseholdSheet(detector: detector),
  );
}

class _HouseholdSheet extends StatefulWidget {
  final Detector detector;
  const _HouseholdSheet({required this.detector});

  @override
  State<_HouseholdSheet> createState() => _HouseholdSheetState();
}

class _HouseholdSheetState extends State<_HouseholdSheet> {
  final _api = ApiService();
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  List<DetectorMember>? _members;
  bool _busy = false;
  String? _error;
  String? _notice;

  Detector get d => widget.detector;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final members = await _api.fetchMembers(d.id);
      if (mounted) setState(() => _members = members);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final m = await _api.addMember(d.id, cleanEmail(_email.text));
      if (!mounted) return;
      _email.clear();
      setState(() {
        _members = [...?_members, m];
        _notice = m.pending
            ? 'Invite sent to ${m.email}. They get access once they create a NotiFire account with that email.'
            : '${m.name.isEmpty ? m.email : m.name} now gets the ${d.room} alerts.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(DetectorMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.name.isEmpty ? m.email : m.name}?'),
        content: Text('They will stop seeing the ${d.room} detector and getting its alerts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.removeMember(d.id, m.id);
      if (mounted) setState(() => _members = _members?.where((x) => x.id != m.id).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.6);
    final members = _members;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(d.isOwner ? 'Share with household' : 'Who gets these alerts',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                d.isOwner
                    ? 'People you add see the ${d.room} detector and get its alerts on their own phones. Only you can change or delete it.'
                    : '${d.ownerName} shared the ${d.room} detector with these people.',
                style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
              title: Text(d.isOwner ? 'You' : d.ownerName),
              subtitle: Text('Owner', style: TextStyle(color: muted)),
            ),
            if (members == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final m in members ?? <DetectorMember>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                      child: Icon(m.pending ? Icons.schedule : Icons.person_outline)),
                  title: Text(m.name.isEmpty ? m.email : m.name),
                  subtitle: Text(
                      m.pending ? '${m.email} • Invited, no account yet' : m.email,
                      style: TextStyle(color: muted)),
                  trailing: d.isOwner
                      ? IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => _remove(m))
                      : null,
                ),
            if (d.isOwner) ...[
              const SizedBox(height: 12),
              Form(
                key: _form,
                child: TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                      labelText: 'Their email', prefixIcon: Icon(Icons.person_add_alt)),
                  validator: validateEmail,
                ),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_notice!, style: const TextStyle(color: Colors.greenAccent)),
                ),
              if (_error != null) ErrorText(_error!),
              const SizedBox(height: 14),
              BusyButton(label: 'Add person', busy: _busy, onPressed: _add),
            ] else if (_error != null)
              ErrorText(_error!),
          ],
        ),
      ),
    );
  }
}
