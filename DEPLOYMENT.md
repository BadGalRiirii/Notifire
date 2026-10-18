# NotiFire — Going live

This guide puts NotiFire into production: the server on **Render**, the
database on **Supabase** (already set up), verification emails through
**Gmail**, and push notifications through **Firebase**. Do the steps in order.
Each one says exactly what to copy and where to paste it.

**Never paste passwords, keys or connection strings into chats, screenshots
or GitHub.** They go only into the places named below.

---

## Step 1: Gmail App Password (for verification codes)

The server sends 6-digit codes from a Gmail account. A normal Gmail password
won't work; Google requires an **App Password**.

1. Use the Gmail account the emails should come from (for example a new
   `notifire.alerts@gmail.com`, or your own).
2. Turn on **2-Step Verification**: <https://myaccount.google.com/security>
   → *How you sign in to Google* → **2-Step Verification**.
3. Open <https://myaccount.google.com/apppasswords>, type the name
   `NotiFire`, then click **Create**.
4. Google shows a **16-letter password** (like `abcd efgh ijkl mnop`). Copy it
   **without the spaces**. You'll paste it in Step 4 as `EMAIL_HOST_PASSWORD`.

To test it on your PC, put both values in `backend/.env`:
```
EMAIL_HOST_USER=notifire.alerts@gmail.com
EMAIL_HOST_PASSWORD=abcdefghijklmnop
```

---

## Step 2: Firebase project (for push notifications)

Firebase is used **only** to deliver notifications to phones. It's free.

1. Go to <https://console.firebase.google.com> → **Create a project**.
   - Name: `NotiFire`
   - Google Analytics: **off** (not needed)
2. On the project page, click the **Android** icon (*Add app*):
   - **Android package name:** `io.github.badgalriirii.notifire`
     (type it exactly. It's the app's permanent ID.)
   - App nickname: `NotiFire`. Leave SHA-1 empty.
   - Click **Register app**, then **Download google-services.json**.
   - Skip the remaining wizard steps (the project is already configured).
3. Put the downloaded file here (it's git-ignored):
   ```
   mobile/android/app/google-services.json
   ```
4. Get the **server key file**: ⚙️ **Project settings** → **Service accounts**
   tab → **Generate new private key** → **Generate key**. A `.json` file
   downloads. Keep it private: it lets anyone send notifications as
   NotiFire.
   - For your PC: save it as `backend/firebase-service-account.json` and set
     `FIREBASE_CREDENTIALS=firebase-service-account.json` in `backend/.env`.
     (The file is git-ignored.)
   - For Render (Step 4): you'll paste the file's **entire contents**.

---

## Step 3: Push the code to GitHub

Render deploys from your GitHub repository
(`github.com/BadGalRiirii/Notifire`). Commit and push the latest code to
`main`. Secret files (`.env`, signing key, Firebase files) are git-ignored and
won't be uploaded.

After the push, open the repo's **Actions** tab. The **CI** workflow runs
the backend and app tests. It should turn green ✔.

---

## Step 4: Deploy on Render

Cost: **Starter web service ≈ $7/month** + **cron job ≈ $1/month**. The free
tier sleeps when idle, which is unsafe for a fire alarm.

1. Sign up at <https://render.com> with your GitHub account and add a payment
   method.
2. **New** → **Blueprint** → select the `Notifire` repository → **Connect**.
   Render reads `render.yaml` and shows two services:
   `notifire-api` (web) and `notifire-offline-check` (cron).
3. Fill in the secret values it asks for:

   | Key | Value |
   |---|---|
   | `DATABASE_URL` | Your Supabase **Session pooler** connection string, the same one as in `backend/.env` |
   | `EMAIL_HOST_USER` | The Gmail address from Step 1 |
   | `EMAIL_HOST_PASSWORD` | The 16-letter App Password (no spaces) |
   | `FIREBASE_CREDENTIALS_JSON` | Open the service-account `.json` from Step 2 in Notepad, select all, copy, paste |
   | `SENTRY_DSN` | Leave empty for now (optional, see Step 7) |

4. Click **Apply**. The first deploy takes ~5 minutes (install → migrate →
   start). When `notifire-api` shows **Live**, copy its address from the top
   of its page, e.g. `https://notifire-api.onrender.com`.
5. Check it: open `https://notifire-api.onrender.com/api/health/` in a
   browser. You should see `{"status":"ok", ...}`.
6. In `notifire-api` → **Settings** → **Build & Deploy**, confirm
   **Auto-Deploy** is set to *After CI checks pass*. Every push to `main`
   then deploys automatically, but only if the tests pass.

---

## Step 5: Build the final app

With `google-services.json` in place (Step 2) and the Render address
(Step 4), build the APK. The address is baked into the app, which is why this
happens last:

```bash
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=https://notifire-api.onrender.com
```

Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`.

**One-time:** uninstall the old NotiFire app before installing this one. The
app's ID and signing key changed to permanent ones. From now on, every new
version installs over the previous one with no uninstall needed.

For each future release, raise the version in `mobile/pubspec.yaml`
(`1.1.0+2` → `1.1.1+3`; the number after `+` must go up), then rebuild.

---

## Step 6: Daily database backups

The free Supabase plan has no backups, so GitHub makes one every night
(`.github/workflows/db-backup.yml`), encrypted and kept for 30 days.

1. GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
   **New repository secret**, twice:
   - `DATABASE_URL`: the Supabase connection string
   - `BACKUP_PASSPHRASE`: a long password you invent. **Write it down
     somewhere safe**: without it a backup can't be opened.
2. **Actions** tab → **Database backup** → **Run workflow** to test it. A
   green ✔ with a `db-backup-…` file under *Artifacts* means it works.

### Restoring a backup
Download the artifact (a `.zip` containing `notifire-….dump.gpg`), then:
```bash
gpg --decrypt notifire-YYYYMMDD-HHMM.dump.gpg > notifire.dump        # asks for BACKUP_PASSPHRASE
pg_restore --clean --if-exists --no-owner -d "$DATABASE_URL" notifire.dump
```

---

## Step 7 (optional): Error tracking with Sentry

Sentry emails you when the server hits an error, with the details needed to
fix it.

1. Sign up at <https://sentry.io> (free plan) → create a **Django** project.
2. Copy the **DSN** (Settings → Client Keys), a URL like
   `https://abc123@o123.ingest.sentry.io/456`.
3. Render → `notifire-api` → **Environment** → set `SENTRY_DSN` → **Save**.

No personal data (emails, IP addresses) is sent to Sentry.

---

## Step 8: Back up the app signing key ⚠️

These two files sign every version of the app:
```
mobile/android/key.properties
mobile/android/app/notifire-release.jks
```
They are deliberately **not** in GitHub. Copy both to a USB drive or a
private cloud folder. **If they're lost, no future version can install as an
update**: every user would have to uninstall and reinstall.

---

## Updating the ESP32 detectors

Flash `firmware/notifire_esp32/notifire_esp32.ino` (Partition Scheme
**Huge APP**). Each detector then needs setting up again from the app,
**Connect device / change Wi-Fi**, so the app can send it the new
`https://` server address.

---

## What protects what

| Area | What's in place |
|---|---|
| Accounts | Email verified with a 6-digit code before detectors can be used; codes expire in 15 min, 5 tries, only a keyed hash stored; password reset by email code; changing password signs out other phones |
| Data access | Token login; every query is scoped to the owner; Supabase Row Level Security blocks its public API |
| Rate limiting | Login/register/codes 10/min per IP or user; uploads 60/min per detector; general API 60/min anonymous, 300/min per user |
| Transport | HTTPS forced with HSTS; ESP32 verifies the server certificate against bundled root CAs |
| Secrets | Only in Render / GitHub secrets / git-ignored files; Django refuses to start in production without a real secret key |
| Deploys | GitHub CI runs backend + app tests; Render deploys only after they pass; migrations run before the new version goes live |
| Availability | Always-on Render instance; health check `/api/health/` (includes the database) with automatic restart; offline-detector alerts every 5 min |
| Recovery | Encrypted nightly backups (30 days); logs in Render's dashboard; optional Sentry alerts |

**Known limits.** Being honest about these matters for a safety device:

- **The detector's buzzer is the primary alarm.** Phone notifications depend
  on Wi-Fi, the internet, Render, Firebase and the phone itself. They're a
  second layer, never a replacement.
- **Render Starter is a single server.** If Render has an outage, uploads
  and notifications stop until it returns, while the buzzers keep working.
  Raising the instance count in Render adds redundancy if needed.
- **The database is in Sydney and the server in Singapore**, so each upload
  takes roughly 0.5–1 s. That's fine for alerts. To make it faster, create the
  Supabase project in Singapore instead.
- **Caching/CDN:** the API serves live sensor data, which must not be cached.
  Static admin files are compressed and cached by WhiteNoise. A CDN would add
  nothing for an app like this.
