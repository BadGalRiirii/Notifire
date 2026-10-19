import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/device_setup.dart';
import '../services/wifi_credentials.dart';
import 'qr_scan_screen.dart';

enum _Step { preparing, searching, connecting, choosingWifi, sending, success, failed }

/// How the setup screen was left (null = back button).
enum SetupResult { done, addAnother, later }

/// Connects a NotiFire ESP32 to Wi-Fi and to [detector], all over Bluetooth.
/// Pops with a [SetupResult].
class SetupDeviceScreen extends StatefulWidget {
  final Detector detector;
  const SetupDeviceScreen({super.key, required this.detector});

  @override
  State<SetupDeviceScreen> createState() => _SetupDeviceScreenState();
}

class _SetupDeviceScreenState extends State<SetupDeviceScreen> {
  final _setup = DeviceSetupService();
  StreamSubscription<SetupDevice>? _scanSub;
  StreamSubscription<void>? _lostSub;

  _Step _step = _Step.preparing;
  String? _problem; // shown on the preparing step (permissions / Bluetooth off)
  bool _permissionSettings = false;

  final Map<String, SetupDevice> _devices = {};
  SetupDevice? _device;

  List<WifiNetwork> _networks = [];
  bool _scanningWifi = false;
  WifiNetwork? _network;
  String _password = '';

  String _sendState = '';
  String _failTitle = '';
  String _failMessage = '';
  _Step _retryStep = _Step.searching;
  bool _reaskPassword = false;

  @override
  void initState() {
    super.initState();
    // A free server may be asleep; start waking it now so the detector's
    // final "checking server" step doesn't wait up to a minute.
    ApiService().wakeServer();
    WifiCredentials.instance.savedNetworks().then((saved) {
      if (mounted) setState(() => _savedNetworks = saved);
    });
    _lostSub = _setup.connectionLost.listen((_) {
      if (_step == _Step.choosingWifi || _step == _Step.sending) {
        _fail('Bluetooth connection lost',
            'Keep your phone close to the detector and try again.',
            retry: _Step.searching);
      }
    });
    _prepare();
  }

  Timer? _slowTimer;
  Set<String> _savedNetworks = {}; // Wi-Fi with a remembered password
  bool _searchingLong = false;

  @override
  void dispose() {
    _slowTimer?.cancel();
    _scanSub?.cancel();
    _lostSub?.cancel();
    _setup.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- steps --

  Future<void> _prepare() async {
    setState(() {
      _step = _Step.preparing;
      _problem = null;
    });
    final problem = await _setup.prepare();
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _problem = problem;
        _permissionSettings = problem.contains('app settings');
      });
      return;
    }
    _startSearch();
  }

  void _startSearch() {
    _scanSub?.cancel();
    _setup.disconnect();
    _slowTimer?.cancel();
    setState(() {
      _step = _Step.searching;
      _devices.clear();
      _device = null;
      _searchingLong = false;
    });
    // Nothing after 10 s almost always means the detector isn't in setup
    // mode (light not blinking) — say so clearly.
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _step == _Step.searching && _devices.isEmpty) {
        setState(() => _searchingLong = true);
      }
    });
    _scanSub = _setup.scan().listen((d) {
      if (!mounted) return;
      setState(() => _devices[d.id] = d);
    }, onError: (Object e) {
      if (mounted) {
        _fail('Could not search for devices',
            'Check that Bluetooth is on and try again.', retry: _Step.preparing);
      }
    });
  }

  Future<void> _connect(SetupDevice device) async {
    await _scanSub?.cancel();
    _scanSub = null;
    setState(() {
      _device = device;
      _step = _Step.connecting;
    });
    try {
      await _setup.connect(device);
      if (!mounted) return;
      setState(() => _step = _Step.choosingWifi);
      await _scanWifi();
    } on DeviceSetupException catch (e) {
      _fail('Could not connect', e.message, retry: _Step.searching);
    }
  }

  Future<void> _scanWifi() async {
    setState(() => _scanningWifi = true);
    try {
      final list = await _setup.scanWifi();
      if (mounted) setState(() => _networks = list);
    } on DeviceSetupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _scanningWifi = false);
    }
  }

  Future<void> _identify() async {
    try {
      await _setup.identify();
    } on DeviceSetupException catch (e) {
      _fail('Bluetooth connection lost', e.message, retry: _Step.searching);
    }
  }

  Future<void> _pickNetwork(WifiNetwork network) async {
    String? password = '';
    if (network.secure) {
      // Retry after a wrong password: show what was typed. Otherwise use the
      // password remembered from an earlier detector, if any.
      final initial = network.ssid == _network?.ssid
          ? _password
          : await WifiCredentials.instance.passwordFor(network.ssid) ?? '';
      if (!mounted) return;
      password = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PasswordSheet(
            ssid: network.ssid,
            initial: initial,
            remembered: initial.isNotEmpty && network.ssid != _network?.ssid),
      );
      if (password == null) return; // cancelled
    }
    _network = network;
    _password = password;
    await _send();
  }

  /// Wi-Fi from a QR code: connects straight away, no typing.
  Future<void> _scanQr() async {
    final qr = await Navigator.of(context)
        .push<WifiQr>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (qr == null || !mounted) return;
    final seen = _networks.where((n) => n.ssid == qr.ssid).toList();
    if (seen.isEmpty) {
      final tryAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('"${qr.ssid}" not found nearby'),
          content: const Text(
              'The detector can\'t see this network. It may be a 5 GHz network (detectors need 2.4 GHz), '
              'or too far from the router.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Try anyway')),
          ],
        ),
      );
      if (tryAnyway != true) return;
    }
    _network = seen.isNotEmpty
        ? seen.first
        : WifiNetwork(ssid: qr.ssid, rssi: -100, secure: !qr.open);
    _password = qr.password;
    await _send();
  }

  Future<void> _send() async {
    setState(() {
      _step = _Step.sending;
      _sendState = 'sending';
    });
    // Remember when the server last heard from this detector, so we can tell
    // when the first reading after setup arrives.
    try {
      _baselineSeen = (await ApiService().fetchDetector(widget.detector.id)).lastSeenAt;
    } on ApiException {
      _baselineSeen = widget.detector.lastSeenAt;
    }
    if (!mounted) return;
    await for (final status in _setup.provision(
      ssid: _network!.ssid,
      password: _password,
      code: widget.detector.code,
      server: AppConfig.baseUrl,
    )) {
      if (!mounted) return;
      if (status.state == 'done') {
        await _setup.disconnect();
        // Joined the Wi-Fi: remember the password for the next detector.
        if (_password.isNotEmpty) {
          await WifiCredentials.instance.save(_network!.ssid, _password);
        }
        await _waitForOnline();
        return;
      }
      if (status.state == 'failed') {
        _failFromReason(status.reason);
        return;
      }
      setState(() => _sendState = status.state);
    }
  }

  DateTime? _baselineSeen;

  /// The detector saved its settings and restarted (Bluetooth off). Setup is
  /// confirmed when its first reading reaches the server: after the restart
  /// and a 20 s sensor warm-up, usually within a minute.
  Future<void> _waitForOnline() async {
    setState(() {
      _step = _Step.sending;
      _sendState = 'waiting_online';
    });
    final api = ApiService();
    final deadline = DateTime.now().add(const Duration(seconds: 100));
    while (mounted && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final d = await api.fetchDetector(widget.detector.id);
        if (d.lastSeenAt != null && d.lastSeenAt != _baselineSeen) {
          if (mounted) setState(() => _step = _Step.success);
          return;
        }
      } on ApiException {
        // server waking up / brief network blip — keep waiting
      }
    }
    if (mounted) _failFromReason('not_online');
  }

  void _failFromReason(String? reason) {
    switch (reason) {
      case 'wrong_password':
        _fail('Wrong Wi-Fi password',
            'The password for "${_network!.ssid}" is incorrect. Check it and try again.',
            retry: _Step.choosingWifi, reaskPassword: true);
      case 'network_not_found':
        _fail('Wi-Fi not found',
            'The detector could not find "${_network!.ssid}". Move it closer to your router and try again.',
            retry: _Step.choosingWifi);
      case 'server_unreachable':
        _fail('Can\'t reach the NotiFire server',
            'The detector joined your Wi-Fi but could not reach the server at ${AppConfig.baseUrl}. '
                'Make sure this Wi-Fi has internet access, then try again.',
            retry: _Step.choosingWifi);
      case 'bad_code':
        _fail('Detector not recognized',
            'The server did not accept this detector. Go back, delete it, and add it again.',
            retry: _Step.choosingWifi);
      case 'not_online':
        _fail('Not online yet',
            'The detector joined your Wi-Fi and restarted, but no reading has reached NotiFire yet. '
                'Give it another minute — or if it keeps failing, hold BOOT for 5 seconds and set it up again.',
            retry: _Step.sending);
      case 'no_response':
        _fail('The detector stopped responding',
            'Keep your phone close to it and try again.', retry: _Step.searching);
      default:
        _fail('Could not connect to Wi-Fi',
            'The detector could not join "${_network!.ssid}". Check the password and that it is a 2.4 GHz network.',
            retry: _Step.choosingWifi);
    }
  }

  void _fail(String title, String message,
      {required _Step retry, bool reaskPassword = false}) {
    if (!mounted) return;
    setState(() {
      _step = _Step.failed;
      _failTitle = title;
      _failMessage = message;
      _retryStep = retry;
      _reaskPassword = reaskPassword;
    });
  }

  Future<void> _retry() async {
    switch (_retryStep) {
      case _Step.preparing:
        await _prepare();
      case _Step.sending:
        await _waitForOnline(); // "Not online yet" → keep waiting
      case _Step.choosingWifi:
        setState(() => _step = _Step.choosingWifi);
        if (_reaskPassword && _network != null) {
          await _pickNetwork(_network!);
        } else if (_networks.isEmpty) {
          await _scanWifi();
        }
      default:
        _startSearch();
    }
  }

  // ---------------------------------------------------------------- UI --

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Connect ${widget.detector.room} detector'),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(_step), child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.preparing:
        return _problem == null
            ? const _Centered(
                icon: Icons.bluetooth, title: 'Getting ready…', busy: true)
            : _Centered(
                icon: Icons.bluetooth_disabled,
                title: 'Bluetooth needed',
                message: _problem,
                actions: [
                  if (_permissionSettings)
                    const FilledButton(
                        onPressed: openAppSettings,
                        child: Text('Open app settings')),
                  OutlinedButton(
                      onPressed: _prepare, child: const Text('Try again')),
                ],
              );
      case _Step.searching:
        return _searchingView();
      case _Step.connecting:
        return _Centered(
          icon: Icons.bluetooth_connected,
          title: 'Connecting to ${_device?.name ?? 'detector'}…',
          busy: true,
        );
      case _Step.choosingWifi:
        return _wifiView();
      case _Step.sending:
        return _sendingView();
      case _Step.success:
        return _Centered(
          icon: Icons.check_circle,
          iconColor: Colors.greenAccent,
          title: '${widget.detector.room} detector is online!',
          message: 'Its first reading has arrived. You will be alerted if it senses smoke, gas or heat.',
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(SetupResult.done),
              child: const Text('Done'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(SetupResult.addAnother),
              icon: const Icon(Icons.add),
              label: const Text('Add another detector'),
            ),
          ],
        );
      case _Step.failed:
        return _Centered(
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
          title: _failTitle,
          message: _failMessage,
          actions: [
            FilledButton(
                onPressed: _retry,
                child: Text(_retryStep == _Step.sending ? 'Keep waiting' : 'Try again')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(SetupResult.later),
                child: const Text('Set up later')),
          ],
        );
    }
  }

  Widget _searchingView() {
    final devices = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final muted = Colors.white.withValues(alpha: 0.65);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // The one thing users must do first — shown up front, not hidden.
        Card(
          color: const Color(0xFFFF7043).withValues(alpha: 0.12),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb, color: Color(0xFFFF7043), size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Is the light on the detector blinking?',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('It must be blinking to be found.'),
                      SizedBox(height: 8),
                      Text('Not blinking? Hold the detector\'s BOOT button for 5 seconds. '
                          'It restarts and the light starts blinking.',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                Icon(Icons.bluetooth_searching, size: 26),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(devices.isEmpty ? 'Looking for your detector…' : 'Detector found',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Keep your phone close to it.',
            textAlign: TextAlign.center, style: TextStyle(color: muted)),
        if (_searchingLong && devices.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'Still looking… The detector only appears while its light is blinking. '
                      'If it is not blinking, hold BOOT for 5 seconds.'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        if (devices.isNotEmpty) ...[
          Text(devices.length == 1 ? 'Tap your device' : 'Found ${devices.length} devices',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (devices.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Tap one — it will beep so you can check it is the device for ${widget.detector.room}. Usually the nearest is at the top.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          for (final d in devices)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sensors, color: Color(0xFFFF7043)),
                title: Text(d.name),
                subtitle: Text(d.rssi > -70 ? 'Nearby' : 'Far away — move closer'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _connect(d),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: const ExpansionTile(
              leading: Icon(Icons.help_outline),
              title: Text('Device not showing up?'),
              childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Tip('Make sure the detector is plugged in and powered on.'),
                _Tip('Keep your phone within a few meters of the detector.'),
                _Tip('Make sure Bluetooth is on. On Android 11 or older, Location must also be on.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _wifiView() {
    final muted = Colors.white.withValues(alpha: 0.65);
    return RefreshIndicator(
      onRefresh: _scanWifi,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.volume_up, color: Color(0xFFFF7043), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Connected to ${_device?.name ?? 'detector'} — it just beeped.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Setting up more than one? Make sure the beeping device is the one for ${widget.detector.room}.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _identify,
                        icon: const Icon(Icons.campaign_outlined, size: 18),
                        label: const Text('Beep again'),
                      ),
                      TextButton.icon(
                        onPressed: _startSearch,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Not this one'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Choose your home Wi-Fi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'The detector shows the networks it can use. 5 GHz networks are not listed — that is normal.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            onPressed: _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Wi-Fi QR code'),
          ),
          const SizedBox(height: 14),
          if (_scanningWifi && _networks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Scanning for Wi-Fi…'),
                ],
              ),
            )
          else if (_networks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Text('No Wi-Fi networks found.'),
                  const SizedBox(height: 4),
                  Text(
                    'Make sure your router has 2.4 GHz Wi-Fi turned on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final n in _networks)
                    ListTile(
                      leading: Icon(_wifiIcon(n.bars)),
                      title: Text(n.ssid, overflow: TextOverflow.ellipsis),
                      subtitle: _savedNetworks.contains(n.ssid)
                          ? const Text('Password saved',
                              style: TextStyle(color: Colors.greenAccent, fontSize: 12))
                          : n.bars == 0
                              ? const Text('Weak signal')
                              : null,
                      trailing: n.secure
                          ? const Icon(Icons.lock_outline, size: 18)
                          : null,
                      onTap: () => _pickNetwork(n),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _scanningWifi ? null : _scanWifi,
              icon: _scanningWifi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('Scan again'),
            ),
          ),
        ],
      ),
    );
  }

  IconData _wifiIcon(int bars) => switch (bars) {
        3 => Icons.wifi,
        2 => Icons.wifi_2_bar,
        1 => Icons.wifi_1_bar,
        _ => Icons.wifi_1_bar,
      };

  Widget _sendingView() {
    // Which of the three rows is in progress; earlier rows show as done.
    final stage = switch (_sendState) {
      'connecting_wifi' => 1,
      'wifi_connected' || 'checking_server' || 'waiting_online' => 2,
      _ => 0,
    };
    final steps = [
      'Sending Wi-Fi details',
      'Connecting to "${_network?.ssid}"',
      'Waiting for the first reading',
    ];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi_tethering, size: 56, color: Color(0xFFFF7043)),
          const SizedBox(height: 16),
          const Text('Setting up your detector…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
              _sendState == 'waiting_online'
                  ? 'The detector is restarting and warming up its sensors. This takes about a minute.'
                  : 'This takes a few seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
          const SizedBox(height: 28),
          for (var i = 0; i < steps.length; i++)
            _ProgressRow(label: steps[i], done: stage > i, active: stage == i),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- widgets --

class _PasswordSheet extends StatefulWidget {
  final String ssid;
  final String initial;
  final bool remembered; // initial came from an earlier, successful setup
  const _PasswordSheet({required this.ssid, required this.initial, this.remembered = false});

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _hidden = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Password for "${widget.ssid}"',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Wi-Fi password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.remembered
                ? 'Saved password filled in from your last setup — just tap Connect.'
                : 'Sent only to your detector over Bluetooth, and remembered (encrypted) on this phone '
                    'for your next detector. NotiFire\'s server never receives it.',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, value, __) => FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: value.text.isEmpty ? null : _submit,
              child: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  const _ProgressRow(
      {required this.label, required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    final Widget icon = done
        ? const Icon(Icons.check_circle, color: Colors.greenAccent)
        : active
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(Icons.radio_button_unchecked,
                color: Colors.white.withValues(alpha: 0.3));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    color: done || active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45))),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? message;
  final bool busy;
  final List<Widget> actions;

  const _Centered({
    required this.icon,
    required this.title,
    this.iconColor,
    this.message,
    this.busy = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 64, color: iconColor ?? const Color(0xFFFF7043)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.7))),
            ],
            if (busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              for (final a in actions)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
