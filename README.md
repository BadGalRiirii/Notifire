# NotiFire 🔥

**Solar-Powered IoT-Based Smoke and Fire Detection System for Household Protection in Cagayan de Oro City**
Grade 11 STEM 24 — Group 3

Full-stack system implementing Chapter 3 methodology:

```
ESP32 (MQ-5 + DHT22)  ──HTTP POST──►  Django REST backend  ◄──polling──  Flutter app
        ▲                                    │
        └── syncs MQ-5 toggle ◄──────────────┤
                                             └──(optional)──► Firebase Realtime DB
```

No hardware yet? No problem — a **fake-data simulator** posts realistic readings
through the exact same API the real ESP32 will use.

---

## Project structure

```
notifire/
├── backend/     Django REST API + fake sensor simulator + optional Firebase mirror
├── mobile/      Flutter app (PPM gauge, temp/humidity, MQ-5 toggle, history logs)
└── firmware/    ESP32 Arduino sketch (works in fake-data mode, hardware-ready)
```

## Thresholds (from Chapter 3)

| Level   | Condition                                                    |
|---------|--------------------------------------------------------------|
| DANGER  | ppm > 1000 **OR** temp ≥ 55°C **OR** humidity ≥ 85%RH         |
| WARNING | ppm > 700 **OR** temp ≥ 45°C **OR** humidity ≥ 82%RH          |
| SAFE    | everything below warning levels                               |

Only **WARNING** and **DANGER** events are saved to History logs (with a
60-second cooldown so a sustained alarm doesn't flood the list).

---

## 1. Backend (Django)

```bash
cd backend
python -m venv venv
# Windows: venv\Scripts\activate     macOS/Linux: source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

In a **second terminal** (same venv), start the fake sensor:

```bash
python manage.py simulate_sensor                    # normal, with random spikes
python manage.py simulate_sensor --scenario fire    # force a DANGER event
python manage.py simulate_sensor --scenario warning
python manage.py simulate_sensor --scenario humidity
python manage.py simulate_sensor --interval 1       # faster updates
```

### API endpoints

| Method | URL                     | Purpose                                        |
|--------|-------------------------|------------------------------------------------|
| GET    | `/api/health/`          | Health check                                   |
| POST   | `/api/readings/ingest/` | ESP32/simulator pushes `{ppm, temperature, humidity}` |
| GET    | `/api/readings/latest/` | Latest reading + device state (dashboard)      |
| GET    | `/api/readings/history/`| Recent raw readings (`?limit=50`) for charts   |
| GET    | `/api/logs/`            | WARNING/DANGER history (`?level=DANGER&limit=100`) |
| GET/POST | `/api/device/`        | Get / set `{"mq5_enabled": true|false}`        |

Django admin available at `/admin/` (`python manage.py createsuperuser`).

### Firebase (optional)

The system runs fully local on SQLite. To also mirror data to Firebase
Realtime Database (as designed in Chapter 3):

1. Firebase Console → Project settings → Service accounts → **Generate new private key**
2. Save the JSON, then set env vars before `runserver`:

```bash
export FIREBASE_CREDENTIALS=/path/to/serviceAccountKey.json
export FIREBASE_DATABASE_URL=https://your-project-default-rtdb.asia-southeast1.firebasedatabase.app
```

Data mirrors to `/notifire/latest`, `/notifire/device`, `/notifire/logs`.

---

## 2. Mobile app (Flutter)

```bash
cd mobile
flutter create .        # generates android/ios/web platform folders (run once)
flutter pub get
```

**Set the backend URL** in `lib/config.dart`:

| Where you run the app | baseUrl                          |
|-----------------------|----------------------------------|
| Android emulator      | `http://10.0.2.2:8000` (default) |
| iOS simulator         | `http://127.0.0.1:8000`          |
| Physical phone        | `http://<your-PC-LAN-IP>:8000`   |
| Chrome (flutter web)  | `http://127.0.0.1:8000`          |

Then:

```bash
flutter run             # or: flutter run -d chrome
```

**Android physical device note:** cleartext HTTP is blocked by default on
Android 9+. After `flutter create .`, add to
`android/app/src/main/AndroidManifest.xml` inside `<application ...>`:

```xml
android:usesCleartextTraffic="true"
```

### App features
- **Dashboard** — SAFE/WARNING/DANGER banner, MQ-5 PPM gauge (danger tick at
  1000 ppm), temperature & humidity cards, **MQ-5 ON/OFF toggle**, auto-refresh
  every 3 s, pull-to-refresh.
- **History** — WARNING/DANGER detection logs with All/Warning/Danger filters.

---

## 3. Firmware (ESP32)

Open `firmware/notifire_esp32/notifire_esp32.ino` in Arduino IDE.

- With `USE_FAKE_DATA true` (default) the board sends simulated readings —
  you can test the full pipeline with just a bare ESP32.
- When the MQ-5 and DHT22 arrive: wire per the pin table in the sketch,
  install the **DHT sensor library** (Adafruit) and **ArduinoJson**, set
  `USE_FAKE_DATA false`, fill in your Wi-Fi credentials and your PC's LAN IP
  in `SERVER_URL`, and flash.
- The backend's ingest response echoes `mq5_enabled`, so the app toggle
  automatically syncs to the board.
- Remember the MQ-5 needs **≥48 h preheating** before readings stabilize
  (Winsen datasheet / Chapter 3 calibration procedure).

---

## Quick demo (no hardware)

```bash
# Terminal 1
cd backend && source venv/bin/activate && python manage.py runserver 0.0.0.0:8000

# Terminal 2
cd backend && source venv/bin/activate && python manage.py simulate_sensor

# Terminal 3
cd mobile && flutter run
```

Watch the dashboard go SAFE → WARNING → DANGER as random spikes occur, flip
the MQ-5 toggle (the simulator output will show `MQ-5 OFF`), and check the
History tab. Run `--scenario fire` to force a danger event on demand.
