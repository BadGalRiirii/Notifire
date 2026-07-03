/// App configuration.
///
/// IMPORTANT — set [baseUrl] to where your Django backend is reachable:
///  * Android emulator  -> http://10.0.2.2:8000
///  * iOS simulator     -> http://127.0.0.1:8000
///  * Physical phone    -> http://<your-PC-LAN-IP>:8000 (same Wi-Fi,
///                         run Django with: python manage.py runserver 0.0.0.0:8000)
///  * Flutter web/desktop -> http://127.0.0.1:8000
class AppConfig {
  static const String baseUrl = 'http://192.168.18.82:8000';

  /// How often the dashboard polls the backend for fresh data.
  static const Duration pollInterval = Duration(seconds: 3);
}
