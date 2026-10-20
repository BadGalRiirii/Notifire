<div align="center">

# 🔥 NotiFire

**Solar-Powered IoT-Based Smoke and Fire Detection System for Household Protection in Cagayan de Oro City**

*Grade 11 STEM 24 · Group 3*

![ESP32](https://img.shields.io/badge/ESP32-Arduino-00979D?logo=arduino&logoColor=white)
![Django](https://img.shields.io/badge/Django-5.2-092E20?logo=django&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Postgres-3FCF8E?logo=supabase&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Push-FFCA28?logo=firebase&logoColor=black)

[User Manual](USER_MANUAL.md) · [Deployment Guide](DEPLOYMENT.md)

</div>

---

NotiFire is a full-stack smoke and fire detection system. ESP32 detectors with
an **MQ-5 gas sensor** and a **DHT22 temperature/humidity sensor** watch each
room, sound a local buzzer the moment something is wrong, and report to a
cloud backend. The backend pushes alerts to every household member's phone,
so you know what is happening at home even when you are away.

## Contents

- [Highlights](#highlights)
- [How it works](#how-it-works)
- [Project structure](#project-structure)
- [Alert levels](#alert-levels)
- [Backend (Django)](#1-backend-django)
- [Mobile app (Flutter)](#2-mobile-app-flutter)
- [Firmware (ESP32)](#3-firmware-esp32)

## Highlights

- 🚨 **Works offline.** Each detector's buzzer and LED go off locally, with or without Wi-Fi.
- 📱 **Push alerts by room.** Get notifications like "🔥 DANGER — Kitchen" on every phone in the household.
- 🏠 **One detector per room.** Every ESP32 runs the same firmware, so there is nothing to edit per device.
- 📶 **Set up from the app.** Connect a detector over Bluetooth, then enter Wi-Fi by hand or scan a Wi-Fi QR code.
- 👨‍👩‍👧 **Household sharing.** Share a detector by email, and everyone it is shared with sees live data and gets alerts.
- 📊 **History and export.** Warning and danger events are logged and can be exported to CSV for Excel or Google Sheets.
- ☁️ **Runs on free tiers.** Uses Render, Supabase, Brevo and Firebase, with CI-gated deploys and database backups.

## How it works

```
 ┌──────────────────────┐   HTTPS POST readings     ┌─────────────────────┐   polling + login   ┌──────────────┐
 │  ESP32 detectors     │ ────────────────────────► │  Django REST API    │ ◄─────────────────► │ Flutter app  │
 │  MQ-5 + DHT22        │   (X-Detector-Code)       │  (Render)           │                     │  (Android)   │
 │  LED + buzzer        │ ◄──────────────────────── │                     │ ──── push alerts ──►│              │
 │  one per room        │   MQ-5 on/off sync        └──────────┬──────────┘   (Firebase FCM)    └──────────────┘
 └──────────────────────┘                                      │
                                                               ▼
                                                     Supabase Postgres
```

1. **Sign up.** The user registers in the app and verifies their email with a 6-digit code.
2. **Add a detector.** On the **Detectors** panel, tap **Add detector** and enter the room (for example *Bedroom*). The server assigns a unique code such as `NF-7K3Q-9XPA`, which the user never needs to type.
3. **Connect it.** The app finds the new ESP32 over **Bluetooth** and shows the Wi-Fi networks the ESP32 can see. It then sends the chosen Wi-Fi network, password, detector code and server address.
4. **Monitor.** The ESP32 uploads readings every ~5 s with its code, and the backend files them under the right detector and household.
5. **Share.** The owner can share a detector with household members by email. They see it live and get its alerts, but only the owner can change or delete it.

> **New to NotiFire?** Read the [User Manual](USER_MANUAL.md). It is also in the app under *Settings → How to use NotiFire*.
> **Deploying?** Follow [DEPLOYMENT.md](DEPLOYMENT.md) for Render hosting, email, Firebase push notifications, backups and the production checklist.

## Project structure

```
notifire/
├── backend/      Django REST API: accounts, detectors, readings, alerts, CSV export
├── mobile/       Flutter app: login, detectors panel, per-room dashboard, history
├── firmware/     ESP32 Arduino sketch: MQ-5 + DHT22 + LED + buzzer, Bluetooth setup
├── .github/      CI (tests + deploy checks) and scheduled database backups
└── render.yaml   One-click Render Blueprint for the backend
```

## Alert levels

The ESP32 (local buzzer) and the backend (app status) use the same **DANGER** thresholds, so the two always agree. The gas value is the **raw MQ-5 ADC reading (0–4095)**. It is uncalibrated and is not in ppm.

| Level | Condition |
|---|---|
| 🔴 **DANGER** | gas > 1500 **or** temp > 40 °C **or** humidity > 85 %RH |
| 🟠 **WARNING** | gas > 1200 **or** temp ≥ 35 °C **or** humidity ≥ 80 %RH *(app only)* |
| 🟢 **SAFE** | everything below warning levels |

- **Changing a threshold:** update both the `*_THRESHOLD` constants in the firmware and `NOTIFIRE_*_DANGER` in `backend/.env`.
- **Sensor failures:** if a DHT22 read fails, the ESP32 sends `null` for that value, and it is left out of the decision.
- **Alarm hold:** a puff of gas can clear in seconds, so alarms are held. The buzzer keeps sounding for **30 s** after the last high reading (firmware `ALARM_HOLD_MS`). The app shows each room at its most severe level from the last **60 s** (backend `ALERT_HOLD`). "Back to normal" is sent after a minute of safe readings.
- **History:** only WARNING and DANGER events are logged, with a 60-second cooldown per detector so a sustained alarm doesn't flood the list.

---

## 1. Backend (Django)

```bash
cd backend
python -m venv venv
# Windows: venv\Scripts\activate     macOS/Linux: source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env              # then set the secret key, allowed hosts and DATABASE_URL
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

On Windows, `.\run_local.ps1` serves the backend with Waitress and reuses database connections, so uploads are noticeably faster than with `runserver`.

### Configuration

The backend reads `backend/.env` on startup. These are the main settings; see [`.env.example`](backend/.env.example) for the full list.

| Variable | Purpose |
|---|---|
| `DJANGO_SECRET_KEY` | A long random value |
| `DJANGO_DEBUG` | `0` in production |
| `DJANGO_ALLOWED_HOSTS` | Comma-separated, e.g. `192.168.100.89,localhost` |
| `DATABASE_URL` | Supabase **Session pooler** connection string (leave blank to use SQLite) |
| `FIREBASE_CREDENTIALS` | Service-account JSON path for push notifications (or put the JSON itself in `FIREBASE_CREDENTIALS_JSON`) |

On Supabase, `migrate` also turns on Row Level Security for every table. This blocks Supabase's public Data API, so only Django can read or write the data.

### Tests

The tests always run on a throwaway SQLite database, never on Supabase:

```bash
python manage.py test monitoring
```

### API reference

App endpoints require `Authorization: Token <token>`. Register and login return the token.

<details>
<summary><b>Accounts</b></summary>

| Method | URL | Purpose |
|---|---|---|
| POST | `/api/auth/register/` | `{name, email, password}` → `{token, user}`, emails a 6-digit code |
| POST | `/api/auth/verify-email/` | `{code}`; required before detectors can be used |
| POST | `/api/auth/resend-code/` | New verification code (60 s cooldown) |
| POST | `/api/auth/login/` | `{email, password}` → `{token, user}` |
| POST | `/api/auth/logout/` | Revoke the token (`{push_token}` stops this phone's alerts) |
| POST | `/api/auth/forgot-password/` | `{email}` → emails a reset code |
| POST | `/api/auth/reset-password/` | `{email, code, new_password}` → logs in, signs out other phones |
| GET / PATCH / DELETE | `/api/auth/me/` | Profile + `notify_danger/warning/offline`; DELETE `{password}` deletes the account |
| POST | `/api/auth/change-password/` | `{current_password, new_password}` → new token |
| POST | `/api/auth/change-email/` (+ `confirm/`) | `{password, new_email}` → code to the new address → `{code}` |
| POST | `/api/push/register/` · `unregister/` | This phone's Firebase token |

</details>

<details>
<summary><b>Detectors, readings and history</b></summary>

| Method | URL | Purpose |
|---|---|---|
| GET / POST | `/api/detectors/` | List the user's detectors / create `{room, name?}` (blank name → "&lt;room&gt; Detector") |
| GET / PATCH / DELETE | `/api/detectors/<id>/` | One detector; PATCH `{room, name, mq5_enabled}` |
| GET | `/api/detectors/<id>/readings/` | Recent raw readings (`?limit=50`) |
| GET | `/api/detectors/<id>/readings/export/` | Raw readings as CSV (`?days=`, max 31) |
| GET | `/api/logs/` | WARNING/DANGER history (`?level=DANGER&detector=<id>`) |
| GET | `/api/logs/<id>/` | One alert with the readings at that moment |
| GET | `/api/logs/export/` | Alert history as CSV (`?level=&detector=&days=`) |

</details>

<details>
<summary><b>Device and system</b></summary>

| Method | URL | Purpose |
|---|---|---|
| GET | `/api/device/check/` | ESP32, end of Bluetooth setup: confirms the server is reachable and the code is valid (`X-Detector-Code`) |
| POST | `/api/readings/ingest/` | ESP32 → `{gas, temperature, humidity}` with header `X-Detector-Code` |
| GET | `/api/health/` | Health check |

</details>

**Rate limits:** login, register and code requests are limited to 10/min, and ESP32 uploads to 60/min per detector. The general API allows 60/min anonymous and 300/min per user.

**Admin:** the Django admin is at `/admin/`. Create an account with `python manage.py createsuperuser`.

**Offline alerts:** `python manage.py check_offline` pushes an alert for any detector that has been silent for more than 3 minutes. In production it runs every 5 minutes.

**Firebase mirror (optional):** set `FIREBASE_DATABASE_URL` as well to mirror data to Firebase Realtime Database under `/notifire/detectors/<id>/latest`, `/state` and `/logs`.

---

## 2. Mobile app (Flutter)

The app connects to the production server by default. To test against a server on your PC instead, pass its address at build time:

```bash
cd mobile
flutter pub get
flutter test
flutter build apk --release
# local server instead of production:
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.100.89:8000
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

### Features

| | |
|---|---|
| **Accounts** | Email + password with 6-digit email verification and password reset by code. The login token is kept in Android's encrypted storage. |
| **Detectors panel** | Every room with live status (SAFE / WARNING / DANGER / OFFLINE / SET UP), plus a red or amber banner for any room in alarm. |
| **Device setup** | Finds the detector over Bluetooth and lists the 2.4 GHz networks it can see. Wi-Fi can be typed or scanned from a QR code. Setup shows live progress and clear errors. |
| **Detector dashboard** | Status banner, gas gauge (0–4095, danger mark at 1500), temperature and humidity, an MQ-5 on/off toggle, and the room's history. |
| **Push notifications** | Room-named danger and warning alerts, plus offline and back-online alerts. Tapping one opens that detector. |
| **Household sharing** | Share a detector by email. Members see it live and get its alerts, but only the owner can edit it. |
| **History & export** | Warning and danger logs across all rooms, filterable by level, exportable as CSV. |
| **Settings** | Change name, email and password, turn each alert type on or off, log out, or delete the account. |

---

## 3. Firmware (ESP32)

Open `firmware/notifire_esp32/notifire_esp32.ino` in the Arduino IDE and flash it as-is to every detector.

| | |
|---|---|
| **Board** | ESP32 Dev Module, ESP32 Arduino Core **3.x** |
| **Partition scheme** | **Huge APP (3MB No OTA/1MB SPIFFS)**. This is required because Wi-Fi + Bluetooth (~1.8 MB) don't fit the default partition. |
| **Libraries** | *DHT sensor library* (Adafruit) + *Adafruit Unified Sensor*, *ArduinoJson* v7 |
| **Wiring** | MQ-5 → GPIO 34 · DHT22 → GPIO 4 · LED → GPIO 2 · Buzzer → GPIO 13 |

### Setting up a detector

1. Power on the ESP32. A new detector starts in **setup mode**: its LED blinks and it advertises over Bluetooth as `NotiFire-XXXX`.
2. In the app, tap **Add detector**, enter the room, then tap **Next: connect device**.
3. Tap the device when it appears, pick your Wi-Fi network (**2.4 GHz only**), and enter the password or scan the network's QR code.
4. The ESP32 joins the Wi-Fi network, confirms with the server, saves its settings and restarts. The LED stops blinking and the room shows as online.

Settings survive power cuts. **Hold the BOOT button for 5 seconds** to reset a detector to setup mode, for example after changing Wi-Fi or moving it to another room. Then use **Connect device / change Wi-Fi** in the app.

### Notes

- The local LED and buzzer alarm works without Wi-Fi, including in setup mode.
- The MQ-5 toggle in the app syncs to the board through the ingest response. Turning the MQ-5 off also mutes the local gas alarm, but the temperature and humidity alarms stay active.
- Bluetooth is only active in setup mode. The Wi-Fi password travels over an unencrypted Bluetooth link during that short window, so set up detectors at home, not in public places.
- The MQ-5 needs **at least 48 h of preheating** before its readings stabilize (Winsen datasheet). The 20-second warm-up at startup only covers the heater.
