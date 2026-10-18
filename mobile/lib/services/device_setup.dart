import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

/// A NotiFire ESP32 found over Bluetooth while it is in setup mode.
class SetupDevice {
  final String id;
  final String name; // "NotiFire-XXXX"
  final int rssi;
  SetupDevice({required this.id, required this.name, required this.rssi});
}

/// A Wi-Fi network the ESP32 itself can see (so only 2.4 GHz ones).
class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool secure;
  WifiNetwork({required this.ssid, required this.rssi, required this.secure});

  /// 0–3 bars.
  int get bars => rssi >= -55 ? 3 : rssi >= -67 ? 2 : rssi >= -78 ? 1 : 0;
}

/// Progress update from the ESP32 while it joins Wi-Fi.
class SetupStatus {
  /// connecting_wifi | wifi_connected | checking_server | done | failed
  final String state;
  final String? reason; // when failed: wrong_password, network_not_found, ...
  final String? room; // when done
  SetupStatus(this.state, {this.reason, this.room});

  bool get isFinal => state == 'done' || state == 'failed';
}

class DeviceSetupException implements Exception {
  final String message;
  DeviceSetupException(this.message);
  @override
  String toString() => message;
}

/// Talks to a NotiFire ESP32 in setup mode over Bluetooth Low Energy.
///
/// Protocol (must match firmware/notifire_esp32/notifire_esp32.ino):
/// the app writes JSON commands to the command characteristic and receives
/// JSON events as notifications on the event characteristic.
///   {"cmd":"hello"}  → {"type":"hello","device":..,"fw":..} (device beeps)
///   {"cmd":"identify"} → device beeps + flashes its LED
///   {"cmd":"scan"}   → {"type":"network",...} × n, then {"type":"scan_done"}
///   {"cmd":"provision","ssid","password","code","server"}
///                    → {"type":"status","state":...} until done/failed
class DeviceSetupService {
  static final serviceUuid = Uuid.parse('8f3b0001-6c4e-4f1a-9a57-2b1c7e5d4a10');
  static final _commandUuid = Uuid.parse('8f3b0002-6c4e-4f1a-9a57-2b1c7e5d4a10');
  static final _eventUuid = Uuid.parse('8f3b0003-6c4e-4f1a-9a57-2b1c7e5d4a10');
  static const devicePrefix = 'NotiFire-';

  final _ble = FlutterReactiveBle();
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _eventSub;
  String? _deviceId;
  bool _expectDisconnect = false;

  /// Fires if the Bluetooth link drops unexpectedly.
  final _lost = StreamController<void>.broadcast();
  Stream<void> get connectionLost => _lost.stream;

  /// Asks for Bluetooth permissions and checks Bluetooth is on.
  /// Returns a user-facing problem, or null when ready to scan.
  Future<String?> prepare() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Only needed (and only declared) on Android 11 and older.
      Permission.locationWhenInUse,
    ].request();
    final scan = results[Permission.bluetoothScan];
    final connect = results[Permission.bluetoothConnect];
    if (scan != PermissionStatus.granted || connect != PermissionStatus.granted) {
      if (scan == PermissionStatus.permanentlyDenied ||
          connect == PermissionStatus.permanentlyDenied) {
        return 'Allow "Nearby devices" for NotiFire in your phone\'s app settings, then try again.';
      }
      return 'NotiFire needs the "Nearby devices" permission to find your detector.';
    }

    final status = await _ble.statusStream
        .firstWhere((s) => s != BleStatus.unknown)
        .timeout(const Duration(seconds: 5), onTimeout: () => BleStatus.unknown);
    return switch (status) {
      BleStatus.ready => null,
      BleStatus.poweredOff => 'Turn on Bluetooth to find your detector.',
      BleStatus.unsupported => 'This phone does not support Bluetooth Low Energy.',
      BleStatus.locationServicesDisabled =>
        'Turn on Location (needed for Bluetooth on older Android versions).',
      _ => 'Bluetooth is not available right now. Check it is turned on.',
    };
  }

  /// NotiFire devices in setup mode nearby. Cancel the subscription to stop.
  ///
  /// Filtered to NotiFire's service ID: Android runs filtered scans in the
  /// Bluetooth chip, so results arrive sooner and are throttled less than a
  /// scan for every device around. (Already-set-up detectors don't
  /// advertise at all — only those in setup mode, light blinking.)
  Stream<SetupDevice> scan() {
    return _ble
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .where((d) =>
            d.name.startsWith(devicePrefix) || d.serviceUuids.contains(serviceUuid))
        .map((d) => SetupDevice(
              id: d.id,
              name: d.name.isEmpty ? 'NotiFire device' : d.name,
              rssi: d.rssi,
            ));
  }

  Future<void> connect(SetupDevice device) async {
    await disconnect();
    _expectDisconnect = false;
    _deviceId = device.id;
    final connected = Completer<void>();

    _connection = _ble
        .connectToDevice(id: device.id, connectionTimeout: const Duration(seconds: 15))
        .listen((update) {
      switch (update.connectionState) {
        case DeviceConnectionState.connected:
          if (!connected.isCompleted) connected.complete();
        case DeviceConnectionState.disconnected:
          if (!connected.isCompleted) {
            connected.completeError(DeviceSetupException(
                'Could not connect to ${device.name}. Keep your phone close to it and try again.'));
          } else if (!_expectDisconnect) {
            _lost.add(null);
          }
        default:
          break;
      }
    }, onError: (Object e) {
      if (!connected.isCompleted) {
        connected.completeError(DeviceSetupException(
            'Could not connect to ${device.name}. Keep your phone close to it and try again.'));
      } else if (!_expectDisconnect) {
        _lost.add(null);
      }
    });

    await connected.future.timeout(const Duration(seconds: 20),
        onTimeout: () => throw DeviceSetupException(
            'Could not connect to ${device.name}. Keep your phone close to it and try again.'));

    // Bigger packets so a Wi-Fi network list entry / the setup message fit.
    try {
      await _ble.requestMtu(deviceId: device.id, mtu: 517);
    } catch (_) {}

    _eventSub = _ble.subscribeToCharacteristic(_char(_eventUuid)).listen((bytes) {
      try {
        final msg = jsonDecode(utf8.decode(bytes));
        if (msg is Map<String, dynamic>) _events.add(msg);
      } catch (_) {
        // ignore malformed notification
      }
    });
    // Give the subscription a moment to be registered on the device.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final hello = _nextEvent((e) => e['type'] == 'hello', const Duration(seconds: 6));
    await _send({'cmd': 'hello'});
    try {
      await hello;
    } on TimeoutException {
      throw DeviceSetupException(
          'This device did not respond. Make sure it is running the latest NotiFire firmware.');
    }
  }

  /// Makes the connected device beep and flash (it also does this on connect),
  /// so the user can tell which one it is when setting up several.
  Future<void> identify() => _send({'cmd': 'identify'});

  /// Asks the ESP32 to scan for Wi-Fi; returns networks strongest first.
  Future<List<WifiNetwork>> scanWifi() async {
    final networks = <String, WifiNetwork>{};
    final done = Completer<void>();
    final sub = _events.stream.listen((e) {
      if (e['type'] == 'network') {
        final n = WifiNetwork(
          ssid: e['ssid'] as String? ?? '',
          rssi: (e['rssi'] as num?)?.toInt() ?? -100,
          secure: e['secure'] as bool? ?? true,
        );
        if (n.ssid.isNotEmpty) networks[n.ssid] = n;
      } else if (e['type'] == 'scan_done' && !done.isCompleted) {
        done.complete();
      }
    });
    try {
      await _send({'cmd': 'scan'});
      await done.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      if (networks.isEmpty) {
        throw DeviceSetupException('The detector did not finish scanning for Wi-Fi. Try again.');
      }
    } finally {
      await sub.cancel();
    }
    return networks.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  /// Sends Wi-Fi + detector details. Emits progress until done or failed.
  Stream<SetupStatus> provision({
    required String ssid,
    required String password,
    required String code,
    required String server,
  }) async* {
    // Listen before sending so no early status is missed.
    final statuses = StreamController<SetupStatus>();
    final sub = _events.stream.where((e) => e['type'] == 'status').listen((e) {
      final status = SetupStatus(
        e['state'] as String? ?? 'failed',
        reason: e['reason'] as String?,
        room: e['room'] as String?,
      );
      // The ESP32 restarts after "done", which drops Bluetooth on purpose.
      if (status.state == 'done') _expectDisconnect = true;
      statuses.add(status);
    });
    _expectDisconnect = false;
    try {
      await _send({
        'cmd': 'provision',
        'ssid': ssid,
        'password': password,
        'code': code,
        'server': server,
      });
      await for (final status
          in statuses.stream.timeout(const Duration(seconds: 45))) {
        yield status;
        if (status.isFinal) break;
      }
    } on TimeoutException {
      yield SetupStatus('failed', reason: 'no_response');
    } finally {
      await sub.cancel();
      await statuses.close();
    }
  }

  Future<void> disconnect() async {
    _expectDisconnect = true;
    await _eventSub?.cancel();
    await _connection?.cancel();
    _eventSub = null;
    _connection = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _lost.close();
  }

  QualifiedCharacteristic _char(Uuid id) => QualifiedCharacteristic(
      serviceId: serviceUuid, characteristicId: id, deviceId: _deviceId!);

  Future<void> _send(Map<String, dynamic> command) async {
    try {
      await _ble.writeCharacteristicWithResponse(_char(_commandUuid),
          value: utf8.encode(jsonEncode(command)));
    } catch (_) {
      throw DeviceSetupException(
          'Lost the Bluetooth connection to the detector. Keep your phone close and try again.');
    }
  }

  Future<Map<String, dynamic>> _nextEvent(
          bool Function(Map<String, dynamic>) test, Duration timeout) =>
      _events.stream.firstWhere(test).timeout(timeout);
}
