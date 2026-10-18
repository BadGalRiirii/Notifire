/// App configuration.
///
/// The backend address is set at build time, so the same code works for
/// local testing and production:
///
///   flutter build apk --release --dart-define=API_BASE_URL=https://notifire-api.onrender.com
///
/// Without --dart-define it falls back to the PC on the local Wi-Fi.
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.89:8000',
  );

  /// How often the dashboard polls the backend for fresh data.
  static const Duration pollInterval = Duration(seconds: 3);

  /// The ESP32 posts every ~5 s; if the newest reading is older than this,
  /// the app shows the detector as offline.
  static const Duration deviceOfflineAfter = Duration(seconds: 30);
}
