# NotiFire — Mobile App

The Flutter (Android) app for NotiFire. It covers accounts, the detectors panel, Bluetooth device setup, live room dashboards, push alerts, household sharing and history export.

```bash
flutter pub get
flutter test
flutter build apk --release
```

The app uses the production server by default. To use a local server, add `--dart-define=API_BASE_URL=http://<your-pc-ip>:8000`.

See the [main README](../README.md) for the full system overview and the [User Manual](../USER_MANUAL.md) for how to use the app.
