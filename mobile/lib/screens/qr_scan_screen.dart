import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/wifi_credentials.dart';

/// Scans a Wi-Fi QR code (router sticker, or another phone's
/// Settings → Wi-Fi → Share). Pops with a [WifiQr], or null if cancelled.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final wifi = WifiQr.parse(code.rawValue);
      if (wifi != null) {
        _done = true;
        Navigator.of(context).pop(wifi);
        return;
      }
    }
    setState(() => _hint = 'That QR code isn\'t a Wi-Fi code. Try the one for your Wi-Fi.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Wi-Fi QR code'),
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraProblem(error: error),
          ),
          // Viewfinder frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF7043), width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint ??
                        'Point the camera at your Wi-Fi QR code — on the router sticker, or on another '
                            'phone (Settings → Wi-Fi → tap your network → Share / QR code).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _hint != null ? Colors.orangeAccent : Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text('Use your 2.4 GHz network (not one ending in "5G").',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  final MobileScannerException error;
  const _CameraProblem({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'NotiFire needs the camera to scan the QR code.'
                  : 'The camera could not be started.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (denied)
              const FilledButton(onPressed: openAppSettings, child: Text('Allow camera in settings')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Type the password instead'),
            ),
          ],
        ),
      ),
    );
  }
}
