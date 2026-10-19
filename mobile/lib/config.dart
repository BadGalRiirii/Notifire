/// App configuration.
///
/// The backend address. Production (Render) by default; to test against a
/// server running on your PC instead:
///
///   flutter build apk --release --dart-define=API_BASE_URL=http://192.168.100.89:8000
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://notifire-api.onrender.com',
  );

  /// How often the dashboard polls the backend for fresh data.
  static const Duration pollInterval = Duration(seconds: 3);

  /// The ESP32 posts every ~5 s; if the newest reading is older than this,
  /// the app shows the detector as offline.
  static const Duration deviceOfflineAfter = Duration(seconds: 30);
}
