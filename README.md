# NotiFire 🔥

**Solar-Powered IoT-Based Smoke and Fire Detection System for Household Protection in Cagayan de Oro City**
Grade 11 STEM 24 — Group 3

Full-stack system implementing Chapter 3 methodology:

```
ESP32 detectors (MQ-5 + DHT22)  ──HTTP POST + detector code──►  Django REST backend  ◄──login + polling──  Flutter app
   (one per room)        ▲                                            │      │
                         └──────── syncs MQ-5 toggle ◄────────────────┘      ├──► Supabase Postgres
                                                                             └──(optional)──► Firebase Realtime DB
```

**How it fits together**

1. A user **registers / logs in** in the app.
2. On the **Detectors** panel they tap **Add detector**, enter the **room**
   (e.g. *Bedroom*) and optionally a **detector name**. The server gives it a
   unique code like `NF-7K3Q-9XPA` (the user never has to see or type it).
3. The app finds the new ESP32 over **Bluetooth**, shows the Wi-Fi networks
   the ESP32 can see, and sends the chosen Wi-Fi + password + detector code +
   server address. Every ESP32 runs the **same firmware** — nothing to edit.
4. The ESP32 sends readings with its code; the backend files them under the
   right detector and user.
5. The owner can **share** a detector with others in the household by email.
   Everyone it's shared with sees it live and gets its alerts on their own
   phone; only the owner can change or delete it.

**Using NotiFire?** See the [User Manual](USER_MANUAL.md), which is also in the app
under Settings → How to use NotiFire.

**Going live?** Follow [DEPLOYMENT.md](DEPLOYMENT.md): Render hosting, email,
Firebase push notifications, backups and the production checklist.

---

## Project structure

```
notifire/
├── backend/     Django REST API (accounts, detectors, readings) + optional Firebase mirror
├── mobile/      Flutter app (login, detectors panel, per-room dashboard, history)
└── firmware/    ESP32 Arduino sketch (MQ-5 + DHT22 + LED + buzzer, Wi-Fi setup portal)
```

## Thresholds

The DANGER thresholds are the same on the ESP32 (local buzzer) and the backend
(app status), so the two always agree. The gas value is the **raw MQ-5 ADC
reading (0–4095)**. It is uncalibrated and is not ppm.

| Level   | Condition                                                    |
|---------|--------------------------------------------------------------|
| DANGER  | gas > 1500 **OR** temp > 40°C **OR** humidity > 85%RH         |
| WARNING | gas > 1200 **OR** temp ≥ 35°C **OR** humidity ≥ 80%RH (app only) |
| SAFE    | everything below warning levels                               |

To change a DANGER threshold, update **both** the `*_THRESHOLD` constants in
the firmware and `NOTIFIRE_*_DANGER` in `backend/.env`. If a DHT22 read fails,
that value is sent as `null` and left out of the decision.

A puff of gas can clear in seconds, so alarms are held: the buzzer keeps
sounding for **30 s** after the last high reading (firmware `ALARM_HOLD_MS`),
and the app shows a room at its most severe level of the last **60 s**
(backend `ALERT_HOLD`). "Back to normal" is sent after a minute of safe
readings.

Only **WARNING** and **DANGER** events are saved to History logs (with a
60-second cooldown per detector so a sustained alarm doesn't flood the list).

---

## 1. Backend (Django)

```bash
cd backend
python -m venv venv
# Windows: venv\Scripts\activate     macOS/Linux: source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env     # then edit: secret key, allowed hosts, DATABASE_URL
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

The backend reads `backend/.env` on startup. Settings worth knowing:

| Variable               | Purpose                                                        |
|------------------------|----------------------------------------------------------------|
| `DJANGO_SECRET_KEY`    | Set a long random value                                        |
| `DJANGO_DEBUG`         | `0` in production                                              |
| `DJANGO_ALLOWED_HOSTS` | Comma-separated, e.g. `192.168.100.89,localhost`               |
| `DATABASE_URL`         | Supabase **Session pooler** connection string; blank = SQLite  |

On Supabase, `migrate` also turns on Row Level Security for every table, which
blocks Supabase's public Data API; only Django can read or write the data.

Run the tests (always on a throwaway SQLite database, never Supabase):

```bash
python manage.py test monitoring
```

### API endpoints

App endpoints need `Authorization: Token <token>` (returned by register/login).

| Method | URL                               | Purpose                                              |
|--------|-----------------------------------|------------------------------------------------------|
| POST   | `/api/auth/register/`             | `{name, email, password}` → `{token, user}`, emails a 6-digit code |
| POST   | `/api/auth/verify-email/`         | `{code}`; required before detectors can be used     |
| POST   | `/api/auth/resend-code/`          | New verification code (60 s cooldown)                |
| POST   | `/api/auth/login/`                | `{email, password}` → `{token, user}`                |
| POST   | `/api/auth/logout/`               | Revoke the token (`{push_token}` stops this phone's alerts) |
| POST   | `/api/auth/forgot-password/`      | `{email}` → emails a reset code                      |
| POST   | `/api/auth/reset-password/`       | `{email, code, new_password}` → logs in, signs out other phones |
| GET/PATCH/DELETE | `/api/auth/me/`         | Profile + `notify_danger/warning/offline`; DELETE `{password}` deletes the account |
| POST   | `/api/auth/change-password/`      | `{current_password, new_password}` → new token       |
| POST   | `/api/auth/change-email/` (+ `confirm/`) | `{password, new_email}` → code to new address → `{code}` |
| POST   | `/api/push/register/` / `unregister/` | This phone's Firebase token                      |
| GET/POST | `/api/detectors/`               | List the user's detectors / create `{room, name?}` (blank name → "<room> Detector") |
| GET/PATCH/DELETE | `/api/detectors/<id>/`  | One detector; PATCH `{room, name, mq5_enabled}`      |
| GET    | `/api/detectors/<id>/readings/`   | Recent raw readings (`?limit=50`)                    |
| GET    | `/api/logs/`                      | WARNING/DANGER history (`?level=DANGER&detector=<id>`) |
| GET    | `/api/logs/<id>/`                 | One alert with the readings at that moment            |
| GET    | `/api/logs/export/`               | Alert history as CSV (`?level=&detector=&days=`)      |
| GET    | `/api/detectors/<id>/readings/export/` | Raw readings as CSV (`?days=`, max 31)           |
| GET    | `/api/device/check/`              | ESP32, end of Bluetooth setup: confirms server reachable + code valid (`X-Detector-Code`) |
| POST   | `/api/readings/ingest/`           | ESP32 → `{gas, temperature, humidity}` with header `X-Detector-Code` |
| GET    | `/api/health/`                    | Health check                                         |

Rate limits: login/register/codes 10/min, ESP32 uploads 60/min per detector,
API 60/min anonymous and 300/min per user. Django admin is at `/admin/`
(`python manage.py createsuperuser`).

`python manage.py check_offline` pushes an alert for detectors silent for more
than 3 minutes (Render runs it every 5 minutes).

### Firebase (optional)

To also mirror data to Firebase Realtime Database, set `FIREBASE_CREDENTIALS`
(service-account JSON path) and `FIREBASE_DATABASE_URL` in `.env`. Data
mirrors to `/notifire/detectors/<id>/latest`, `/state` and `/logs`.

---

## 2. Mobile app (Flutter)

Set the backend URL in `lib/config.dart` (`baseUrl`, e.g.
`http://192.168.100.89:8000` — your PC's Wi-Fi IP). Then:

```bash
cd mobile
flutter pub get
flutter test
flutter build apk --release    # → build/app/outputs/flutter-apk/app-release.apk
```

Plain-HTTP access to the backend is already enabled in
`android/app/src/main/AndroidManifest.xml` (`usesCleartextTraffic`).

### App features
- **Register / Log in**: email + password with a **6-digit email
  verification code**, plus **Forgot password** (reset by emailed code). The
  login token is kept in Android's encrypted storage.
- **Push notifications**: "🔥 DANGER — Kitchen" alerts naming the room,
  plus offline/back-online alerts. Tapping one opens that detector.
- **Settings**: change name, email (confirmed by code) and password; turn
  danger / warning / offline alerts on or off; log out; delete account.
- **Detectors panel** — every room with live status (SAFE / WARNING /
  DANGER / OFFLINE / SET UP), a red/amber banner for any room in alarm, and
  **Add detector** (room + optional detector name) which goes straight into
  Bluetooth device setup.
- **Device setup (Bluetooth)** — finds the NotiFire device, lists the Wi-Fi
  networks it can see (2.4 GHz only), asks for the password, and shows live
  progress with clear errors (wrong password, network not found, server
  unreachable). No hotspot, browser, IP address or code typing.
- **Detector dashboard** — status banner, gas gauge (raw 0–4095, danger tick at
  1500), temperature & humidity, **MQ-5 ON/OFF toggle** for that detector,
  connect device / change Wi-Fi, edit room/name, delete, and that room's history.
- **History** — WARNING/DANGER logs from all detectors (with the room name),
  filterable by level.

---

## 3. Firmware (ESP32)

Open `firmware/notifire_esp32/notifire_esp32.ino` in Arduino IDE and flash it
as-is to every detector — there is nothing to edit per device.

- Wiring: MQ-5 → GPIO 34, DHT22 → GPIO 4, LED → GPIO 2, buzzer → GPIO 13.
- Board: **ESP32 Dev Module**, ESP32 Arduino Core **3.x**.
- **Tools → Partition Scheme → "Huge APP (3MB No OTA/1MB SPIFFS)"** — required;
  Wi-Fi + Bluetooth (~1.8 MB) don't fit the default partition.
- Libraries: **DHT sensor library** (Adafruit, + Adafruit Unified Sensor) and
  **ArduinoJson** (v7). Bluetooth, Wi-Fi, HTTP and Preferences ship with the core.

**Setting up a detector (all in the app)**

1. Power the ESP32. A new one starts in **setup mode**: its LED blinks and it
   advertises over Bluetooth as `NotiFire-XXXX`.
2. In the app: **Add detector** → enter the room → **Next: connect device**.
3. Tap the device when it appears, pick your Wi-Fi (**2.4 GHz** networks only —
   the list comes from the ESP32 itself), and enter the password.
4. The ESP32 joins Wi-Fi, checks that the server accepts its code, saves the
   settings and restarts. The LED stops blinking and the room shows online.

Settings survive power cuts. **Hold the BOOT button for 5 seconds** to clear
them and go back to setup mode (new Wi-Fi, moved to another room, server IP
changed), then use **Connect device / change Wi-Fi** in the app.

Bluetooth is only active in setup mode. The Wi-Fi password travels over an
unencrypted Bluetooth link during that short setup window, so set up
detectors at home rather than in public places.

- The local LED/buzzer alarm works with no Wi-Fi, including while in setup mode.
- The backend's ingest response echoes `mq5_enabled`, so the app toggle syncs
  to that board. Turning it off also mutes the local gas alarm; temperature
  and humidity alarms stay active.
- The MQ-5 needs **≥48 h preheating** before readings stabilize (Winsen
  datasheet). The 20 s startup warm-up only covers the short heater warm-up.
