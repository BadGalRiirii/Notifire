# NotiFire User Manual

**Solar-Powered IoT-Based Smoke and Fire Detection System**

NotiFire watches each room for **smoke, gas and heat**. When it senses
danger, the detector's **buzzer sounds** and the **NotiFire app** tells your
phone *which room* needs attention, even when you're away from home.

The same guide is in the app: **Settings → How to use NotiFire**.

---

## Contents
1. [What's in the box](#1-whats-in-the-box)
2. [Getting started](#2-getting-started)
3. [Adding a detector](#3-adding-a-detector)
4. [What the colours mean](#4-what-the-colours-mean)
5. [When you get an alert](#5-when-you-get-an-alert)
6. [History and exporting](#6-history-and-exporting)
7. [The smoke sensor switch (MQ-5)](#7-the-smoke-sensor-switch-mq-5)
8. [Moving a detector or changing Wi-Fi](#8-moving-a-detector-or-changing-wi-fi)
9. [Sharing with your household](#9-sharing-with-your-household)
10. [Settings](#10-settings)
11. [Troubleshooting](#11-troubleshooting)
12. [Safety](#12-safety)

---

## 1. What's in the box

Each detector has:

| Part | What it does |
|---|---|
| **Smoke/gas sensor (MQ-5)** | Senses smoke and gas (LPG/butane) |
| **Temperature & humidity sensor (DHT22)** | Senses heat and very high humidity |
| **Light (LED)** | **Blinking**: ready to be set up. **Steady on**: alarm. **Off**: normal. |
| **Buzzer** | Sounds when the detector senses danger, with or without Wi-Fi, and keeps sounding for **30 seconds** after the air clears |
| **BOOT button** | Hold for **5 seconds** to reset the detector so it can be set up again |

The detector needs power and a **2.4 GHz** Wi-Fi network. Most home routers
have one. It's often the network whose name does **not** end in "5G".

---

## 2. Getting started

1. Install the NotiFire app and open it.
2. Tap **Create one**, then enter your name, email and a password (at least 8
   characters, not only numbers).
3. Check your email for a **6-digit code** and enter it in the app. If you
   don't see it, look in **Spam** or tap **Resend code**. Codes expire after
   15 minutes.
4. When the app asks to send notifications, tap **Allow**. This is how you
   receive fire alerts.

Forgot your password? On the login screen tap **Forgot password?**, and
we'll email you a code to set a new one.

---

## 3. Adding a detector

1. **Plug in the detector.** Its light **blinks** when it's ready to be set
   up.
   - *Light not blinking?* Hold the **BOOT** button for **5 seconds** until
     the detector restarts and the light blinks.
2. In the app, tap **Add detector**.
3. Choose the **room** (for example *Bedroom*), and optionally give the
   detector a **name**. Tap **Next: connect device**.
4. Allow **Nearby devices** if asked. The app finds the detector over
   Bluetooth. **Tap it.** It **beeps 3 times** so you know it's the right
   one.
5. Choose your **home Wi-Fi** and type its password. Only 2.4 GHz networks
   are listed, which is normal.
   - **No typing:** tap **Scan Wi-Fi QR code** and point the camera at the
     Wi-Fi QR code on your router sticker, or on another phone (*Settings →
     Wi-Fi → tap your network → Share / QR code*).
   - The password is **remembered on your phone** (encrypted), so the next
     detector on the same Wi-Fi fills it in for you. NotiFire's server never
     receives your Wi-Fi password.
6. Wait for **"connected"**. The room now shows live readings.

Setting up several rooms? Tap **Add another detector** after each one.

---

## 4. What the colours mean

| Status | Meaning |
|---|---|
| 🟢 **SAFE** | Everything is normal. |
| 🟡 **WARNING** | Smoke/gas is rising (above 1200) or temperature is 35 °C or more. Check the room. |
| 🔴 **DANGER** | Smoke/gas above 1500, temperature above 40 °C, or humidity above 85 %. **The buzzer sounds.** Stays red for 1 minute after the last high reading. |
| ⚪ **OFFLINE** | The detector stopped sending readings. Check its power and Wi-Fi. |
| 🔵 **SET UP** | The detector hasn't been connected yet. Open it and tap **Connect device**. |

Normal humid weather (75–84 %) does **not** cause a warning.

---

## 5. When you get an alert

- **App open:** a **red** (danger) or **yellow** (warning) pop-up appears.
  Tap **View details**.
- **App closed:** you get a notification such as
  *"🔥 DANGER — Kitchen: Smoke or gas detected"*. Tap it.
- **Alert details** shows:
  - **what triggered it** (e.g. *Smoke or gas detected, level 2346*),
  - **the readings at that moment**, with the one over its limit highlighted,
  - **how the room is right now** (e.g. *Back to normal*).
- **Silencing the buzzer:** tap **OK** on a red pop-up, or open the room and
  tap **Silence buzzer**. The buzzer stops within a few seconds, but the
  detector's light stays on. If the danger is still there after **5 minutes**,
  the buzzer sounds again. Only silence it once you know the room is safe or
  someone is dealing with it.
- Smoke can clear in seconds, so a room stays **DANGER** (or **WARNING**) in
  the app for **1 minute** after the last high reading, so a short puff isn't
  missed. After a full minute of safe readings, the notification changes to
  **"✅ Kitchen is back to normal"** and still says what happened earlier.
- You also get a notice if a detector goes **offline** (loses power or
  Wi-Fi) and when it's **back online**.
- **Works anywhere.** Your phone does not need to be on the home Wi-Fi. At
  work, at school, on another Wi-Fi or on mobile data, the app still shows
  live readings and you still get alerts. Only the **detector** needs the
  home Wi-Fi.
- **Make alerts reliable:** if *Settings* shows **"Alerts may be delayed"**,
  tap **Allow**. Battery saving (strict on Xiaomi, Oppo, Vivo and Realme
  phones) can otherwise hold alerts back while NotiFire is closed.

> **In real danger: get everyone out of the house first, then call 911
> (Bureau of Fire Protection). Don't wait for the app.**

---

## 6. History and exporting

- The **History** tab lists every warning and danger, newest first, with the
  room it came from.
- Filter with **All / Warning / Danger** and the **room** buttons.
- **Tap any entry** to see its details.
- **Export:** tap **Export** on the History tab (or the share icon in a
  room's history):
  1. Choose **Alerts** (warnings and dangers) or **All readings** (every
     reading from one detector).
  2. Choose the **room** and the **period**.
  3. Tap **Export & share**, then save the file to Google Drive or
     Downloads, or send it by Gmail or Messenger.

  The file is a **spreadsheet (CSV)** that opens in **Excel** or **Google
  Sheets**.
- **How long things are kept:** alert history is kept **permanently**.
  Detailed readings (one every ~5 seconds) are kept for **30 days**.

---

## 7. The smoke sensor switch (MQ-5)

Each detector's screen has an **MQ-5 Smoke Sensor** switch.

- **Off:** smoke/gas is ignored for that detector, which is useful while
  cooking with gas. The detector's own gas alarm is muted too.
- **Temperature and humidity alarms keep working.**
- **Remember to turn it back on.**

---

## 8. Moving a detector or changing Wi-Fi

1. Hold the detector's **BOOT** button for **5 seconds** until the light
   blinks.
2. In the app: open the room → **⋮** → **Connect device / change Wi-Fi**.

Other options in the **⋮** menu:
- **Edit room / name**: rename the room or detector.
- **History**: this room's alerts only.
- **Delete detector**: removes it and its history.

**Giving a detector to someone else:** delete it from your account first,
then reset it with **BOOT**. They can then add it to their own account.

---

## 9. Sharing with your household

Everyone at home can get a detector's alerts on their own phone.

1. Open the room → **⋮** → **Share with household**.
2. Type their email and tap **Add person**.
   - **They already use NotiFire:** the detector appears in their app right
     away.
   - **They don't yet:** they get an email. Once they install NotiFire,
     **create an account with that same email** and verify it, and the
     detector appears automatically.
3. They see live readings and History, and get Danger, Warning and Offline
   alerts according to **their own** Settings.

Only you (the owner) can rename, delete or reconnect the detector, switch the
MQ-5 off, or add and remove people. Tap **✕** next to someone to remove them.
Someone you added can leave with **⋮** → **Stop getting this detector**.
Up to 10 people per detector.

---

## 10. Settings

- **Account:** change your name, email (confirmed with a code sent to the
  new address) or password. Changing your password logs out your other phones.
- **Notifications:** choose which alerts you receive:
  - **Danger alerts:** on (strongly recommended)
  - **Warning alerts:** off by default (can be frequent)
  - **Offline alerts:** on
- **Log out**, or **Delete account**, which permanently removes your account,
  detectors and history.

---

## 11. Troubleshooting

| Problem | What to do |
|---|---|
| The app can't find my detector | It only appears while its **light is blinking**. Hold **BOOT** for 5 seconds, keep your phone close, and make sure Bluetooth is on. |
| "Wrong Wi-Fi password" | Check capital letters and spaces. Use the **2.4 GHz** network, not the one ending in "5G". |
| A room shows **OFFLINE** | Check the detector has power and your Wi-Fi works. It reconnects on its own when the Wi-Fi is back. |
| No notifications | **Settings → Notifications**: make sure alerts are on. If it says notifications are off, tap **Turn on**. |
| No email code | Look in **Spam**, then tap **Resend code**. Codes expire after 15 minutes. |
| "Cannot reach server" | Check your phone's internet. If the service was idle it can take up to a minute to wake up, so try again. |
| Login says *"…" is not an email address* | The quotes show what the app read. If it's your name, your phone autofilled the wrong saved login: clear the box and type your email, and delete the wrong entry in your phone's password manager. |
| "Incorrect email or password" | Check the password, or tap **Forgot password?** to get a code by email. |
| The detector works but **my phone gets no alerts** | Alerts go to the account the detector belongs to, and to people it's shared with. Log in with that account, or ask its owner to add you with **Share with household**. |
| A shared detector doesn't appear | Use the **same email** the owner typed, and verify it with the emailed code. Then pull down to refresh the Detectors list. |
| Buzzer sounds but the app says SAFE | The detector may be offline: check its status and Wi-Fi. If it's online, pull down to refresh and check **History**. |

---

## 12. Safety

- **The detector's buzzer is the main alarm.** It works even without Wi-Fi
  or the app.
- **Phone alerts are an extra layer.** The detector needs Wi-Fi, and your
  phone needs internet (any Wi-Fi or mobile data). Share each detector with
  everyone at home so more than one phone is alerted.
- **A new smoke/gas sensor needs about 48 hours** powered on before its
  readings are steady. Expect a few false alarms at first.
- **Test each detector once a month**, for example with a short puff of gas
  from an **unlit** lighter held a safe distance away. Never use a flame.
- Keep detectors away from steam, direct cooking smoke and rain to avoid false
  alarms.
- **In a fire: get out, stay out, and call 911.**
