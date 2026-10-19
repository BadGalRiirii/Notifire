import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// Lets the user export alert history or raw readings as a CSV spreadsheet
/// and share/save it (Google Drive, Gmail, Messenger, Downloads...).
Future<void> showExportSheet(BuildContext context,
    {required List<Detector> detectors, Detector? only}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ExportSheet(detectors: detectors, only: only),
  );
}

enum _What { alerts, readings }

class _ExportSheet extends StatefulWidget {
  final List<Detector> detectors;
  final Detector? only; // opened from one detector's history
  const _ExportSheet({required this.detectors, this.only});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  _What _what = _What.alerts;
  late int? _detectorId = widget.only?.id;
  int _days = 30; // 0 = all time (alerts only)
  bool _busy = false;
  String? _error;

  List<Detector> get _rooms => widget.only != null ? [widget.only!] : widget.detectors;

  List<(int, String)> get _periods => _what == _What.alerts
      ? const [(7, 'Last 7 days'), (30, 'Last 30 days'), (0, 'All time')]
      : const [(1, 'Last 24 hours'), (7, 'Last 7 days'), (30, 'Last 30 days')];

  void _setWhat(_What what) {
    setState(() {
      _what = what;
      _error = null;
      if (what == _What.readings) {
        _detectorId ??= _rooms.isNotEmpty ? _rooms.first.id : null;
        if (_days == 0) _days = 7;
      }
    });
  }

  Future<void> _export() async {
    if (_what == _What.readings && _detectorId == null) {
      setState(() => _error = 'Choose a room.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final (bytes, name) = _what == _What.alerts
          ? await api.downloadCsv('/api/logs/export/', {
              'days': '$_days',
              if (_detectorId != null) 'detector': '$_detectorId',
            })
          : await api.downloadCsv(
              '/api/detectors/$_detectorId/readings/export/', {'days': '$_days'});

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;

      final what = _what == _What.alerts ? 'alert history' : 'readings';
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'NotiFire $what',
        text: 'NotiFire $what (opens in Excel or Google Sheets).',
      ));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the file. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.6);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Export history',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Creates a spreadsheet file (CSV) you can open in Excel or Google Sheets, '
                'then save or send it.',
                style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 18),
            const _Label('What to export'),
            SegmentedButton<_What>(
              segments: const [
                ButtonSegment(
                    value: _What.alerts,
                    icon: Icon(Icons.warning_amber_rounded),
                    label: Text('Alerts')),
                ButtonSegment(
                    value: _What.readings,
                    icon: Icon(Icons.show_chart),
                    label: Text('All readings')),
              ],
              selected: {_what},
              onSelectionChanged: (s) => _setWhat(s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _what == _What.alerts
                  ? 'Every warning and danger, with what triggered it and the readings at that moment.'
                  : 'Every reading one detector sent (about every 5 seconds). Kept for 30 days.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (widget.only == null) ...[
              const SizedBox(height: 18),
              const _Label('Room'),
              DropdownButtonFormField<int?>(
                initialValue: _detectorId,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.meeting_room_outlined)),
                items: [
                  if (_what == _What.alerts)
                    const DropdownMenuItem<int?>(value: null, child: Text('All rooms')),
                  for (final d in _rooms)
                    DropdownMenuItem<int?>(value: d.id, child: Text(d.room)),
                ],
                onChanged: (v) => setState(() => _detectorId = v),
              ),
            ],
            const SizedBox(height: 18),
            const _Label('Period'),
            Wrap(
              spacing: 8,
              children: [
                for (final (days, label) in _periods)
                  ChoiceChip(
                    label: Text(label),
                    selected: _days == days,
                    onSelected: (_) => setState(() => _days = days),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy || _rooms.isEmpty ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              label: Text(_busy ? 'Preparing file…' : 'Export & share'),
            ),
            if (_rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Add a detector first — there is nothing to export yet.',
                    textAlign: TextAlign.center, style: TextStyle(color: muted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}
