/*
 * NotiFire — Solar-Powered IoT-Based Smoke and Fire Detection System
 * ESP32 firmware (Grade 11 STEM 24 — Group 3)
 *
 * Reads MQ-5 (smoke/gas) + DHT22 (temperature/humidity), drives the local
 * LED + buzzer alarm, and POSTs every reading to the Django backend.
 *
 * ONE SKETCH FOR EVERY DETECTOR — nothing to edit per device.
 * Setup is done entirely from the NotiFire app over Bluetooth:
 *   - A new (or reset) ESP32 starts in SETUP MODE: the LED blinks and it
 *     advertises over Bluetooth as "NotiFire-XXXX".
 *   - In the app: Add detector → the app finds the device, asks it to scan
 *     for Wi-Fi, and sends the chosen Wi-Fi + password + detector code +
 *     server address. The ESP32 joins the Wi-Fi, saves everything to flash
 *     and restarts in normal mode (Bluetooth off, so there's memory for
 *     HTTPS); the app confirms setup when the first reading arrives.
 *   - To set it up again (new Wi-Fi, another room), hold BOOT for 5 seconds.
 *
 * The local alarm never depends on Wi-Fi: during setup or with the network
 * down, the buzzer still sounds and readings are simply not uploaded.
 *
 * Wiring:
 *   MQ-5 analog out  -> GPIO 34 (ADC1 — safe to use with Wi-Fi on)
 *   DHT22 data       -> GPIO 4  (10k pull-up to 3.3V)
 *   Status LED       -> GPIO 2  (onboard LED; blinks in setup mode)
 *   Buzzer           -> GPIO 13 (PWM tone)
 *   Reset button     -> GPIO 0  (onboard BOOT button)
 *
 * Board: ESP32 Dev Module, ESP32 Arduino Core 3.x.
 * Tools > Partition Scheme > "Huge APP (3MB No OTA/1MB SPIFFS)" — Wi-Fi +
 * Bluetooth together do not fit in the default partition.
 * Libraries (Arduino IDE > Library Manager):
 *   - "DHT sensor library" by Adafruit (+ Adafruit Unified Sensor)
 *   - ArduinoJson by Benoit Blanchon (v7)
 *   (Bluetooth, Wi-Fi, HTTP and Preferences come with the ESP32 core.)
 */

#include <WiFi.h>
#include <NetworkClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#ifdef CONFIG_BLUEDROID_ENABLED
#include <BLE2902.h>
#endif
#include "DHT.h"
#include "root_ca.h"

#define FW_VERSION "2.6"

const char* INGEST_PATH = "/api/readings/ingest/";

// Bluetooth setup protocol — must match mobile/lib/services/device_setup.dart
#define SETUP_SERVICE_UUID "8f3b0001-6c4e-4f1a-9a57-2b1c7e5d4a10"
#define COMMAND_CHAR_UUID  "8f3b0002-6c4e-4f1a-9a57-2b1c7e5d4a10"  // app -> ESP32 (write)
#define EVENT_CHAR_UUID    "8f3b0003-6c4e-4f1a-9a57-2b1c7e5d4a10"  // ESP32 -> app (notify)

// The server (Render, Singapore) talks to a database in Sydney, so a request
// can take ~1 s. Uploads happen after the alarm is set, so a slow request
// never delays the buzzer — it only delays the next reading slightly.
const uint16_t HTTP_TIMEOUT_MS = 5000;

// ==================== ESP32 PIN CONFIGURATION ====================
#define DHTPIN       4
#define DHTTYPE      DHT22
#define MQ5PIN       34
#define LED_PIN      2
#define BUZZER_PIN   13
#define RESET_PIN    0      // onboard BOOT button (LOW when pressed)

// ==================== BUZZER PWM SETTINGS ====================
#define ALARM_PITCH 2000
#define PWM_RESOLUTION 8

// ==================== SAFETY THRESHOLDS ====================
// Keep these in sync with NOTIFIRE_*_DANGER in backend/notifire_backend/settings.py
const float TEMP_THRESHOLD = 40.0;
const float HIGH_HUMID_THRESHOLD = 85.0;
const int GAS_THRESHOLD = 1500;         // raw 12-bit ADC (0–4095), not ppm

// ==================== TIMING ====================
const unsigned long SENSOR_INTERVAL      = 2000;   // read sensors + drive alarm
const unsigned long UPLOAD_INTERVAL      = 5000;   // send to server (sooner if alarm changes)
const unsigned long WARMUP_MS            = 20000;  // MQ-5 heater warm-up after power-on
const unsigned long RESET_HOLD_MS        = 5000;
const unsigned long WIFI_SETUP_TIMEOUT   = 20000;
const unsigned long SETUP_BLINK_MS       = 500;
// Keep sounding this long after the last high reading: a puff of gas or
// smoke can clear in seconds, and a 2-second chirp is easy to miss.
const unsigned long ALARM_HOLD_MS        = 30000;
// Self-recovery: auto-reconnect can give up after a router restart, and a
// broken TLS connection can keep failing, leaving the detector silent until
// someone unplugs it. Kick Wi-Fi after this long disconnected...
const unsigned long WIFI_RETRY_MS        = 30000;
// ...and restart the board if the server hasn't answered for this long
// (never while the alarm is sounding).
const unsigned long NO_SERVER_RESTART_MS = 600000;  // 10 min

DHT dht(DHTPIN, DHTTYPE);
Preferences prefs;

// One persistent connection to the server: HTTPS (certificate-checked
// against root_ca.h) for https:// addresses, plain for http:// (local tests).
// Reusing it avoids a ~1 s TLS handshake on every upload.
NetworkClientSecure secureClient;
NetworkClient plainClient;
HTTPClient http;

// Saved settings (written by Bluetooth setup)
String wifiSsid, wifiPass, detectorCode, serverUrl;
String deviceName;          // "NotiFire-XXXX"
bool setupMode = false;

// Bluetooth state
BLECharacteristic* eventChar = nullptr;
volatile bool bleConnected = false;
volatile bool commandPending = false;
String pendingCommand;

// Wi-Fi provisioning state machine (setup mode only)
enum ProvState { PROV_IDLE, PROV_CONNECTING, PROV_CHECKING };
ProvState provState = PROV_IDLE;
unsigned long provStartedAt = 0;
volatile uint8_t lastDisconnectReason = 0;
volatile uint8_t authFailures = 0;
String provSsid, provPass, provCode, provServer;

unsigned long lastReadTime = 0;
unsigned long lastUploadAt = 0;
bool lastUploadedAlarm = false;
unsigned long resetPressedAt = 0;
unsigned long lastBlinkAt = 0;
bool warmupDone = false;
bool mq5Enabled = true;     // synced from the app via backend response
bool alarmActive = false;
unsigned long lastTriggerAt = 0;  // last reading over a threshold
bool wasWifiConnected = false;
unsigned long wifiLostAt = 0;       // 0 = connected
unsigned long lastServerReplyAt = 0;  // any HTTP response, even an error

// ==================== SETTINGS ====================
void loadSettings() {
  prefs.begin("notifire", true);
  wifiSsid = prefs.getString("ssid", "");
  wifiPass = prefs.getString("pass", "");
  detectorCode = prefs.getString("code", "");
  serverUrl = prefs.getString("server", "");
  prefs.end();
}

void saveSettings() {
  prefs.begin("notifire", false);
  prefs.putString("ssid", provSsid);
  prefs.putString("pass", provPass);
  prefs.putString("code", provCode);
  prefs.putString("server", provServer);
  prefs.end();
}

// Opens (or reuses) the connection for a request to `url`.
bool beginRequest(const String& url, uint16_t timeoutMs) {
  http.setReuse(true);
  http.setConnectTimeout(timeoutMs);
  http.setTimeout(timeoutMs);
  bool ok = url.startsWith("https://") ? http.begin(secureClient, url)
                                       : http.begin(plainClient, url);
  if (!ok) Serial.println("HTTP: invalid server address");
  return ok;
}

String normalizeServer(String server) {
  server.trim();
  if (server.length() == 0) return server;
  if (!server.startsWith("http://") && !server.startsWith("https://")) {
    server = "http://" + server;
  }
  while (server.endsWith("/")) server.remove(server.length() - 1);
  return server;
}

// Hold BOOT for 5 s: wipe all settings and restart into setup mode.
void checkResetButton() {
  if (digitalRead(RESET_PIN) == LOW) {
    if (resetPressedAt == 0) resetPressedAt = millis();
    if (millis() - resetPressedAt >= RESET_HOLD_MS) {
      Serial.println("BOOT held 5 s — clearing settings and restarting into setup mode...");
      prefs.begin("notifire", false);
      prefs.clear();
      prefs.end();
      WiFi.disconnect(true, true);
      delay(300);
      ESP.restart();
    }
  } else {
    resetPressedAt = 0;
  }
}

// ==================== BLUETOOTH SETUP ====================
class SetupServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleConnected = true;
    Serial.println("Bluetooth: NotiFire app connected");
  }
  void onDisconnect(BLEServer* server) override {
    bleConnected = false;
    Serial.println("Bluetooth: app disconnected");
    BLEDevice::startAdvertising();  // allow the app to reconnect / retry
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    if (commandPending) return;  // still handling the previous command
    pendingCommand = characteristic->getValue();
    commandPending = true;       // handled in loop(), not on the BLE task
  }
};

void sendEvent(JsonDocument& doc) {
  if (eventChar == nullptr) return;
  String json;
  serializeJson(doc, json);
  eventChar->setValue(json);
  if (bleConnected) eventChar->notify();
  delay(15);  // let the BLE stack send before the next notification
}

void sendStatus(const char* state, const char* reason = nullptr) {
  JsonDocument doc;
  doc["type"] = "status";
  doc["state"] = state;
  if (reason) doc["reason"] = reason;
  sendEvent(doc);
}

void startBluetoothSetup() {
  BLEDevice::init(deviceName);
  BLEDevice::setMTU(517);  // room for Wi-Fi password + code in one write
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new SetupServerCallbacks());

  BLEService* service = server->createService(SETUP_SERVICE_UUID);
  BLECharacteristic* commandChar =
      service->createCharacteristic(COMMAND_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  commandChar->setCallbacks(new CommandCallbacks());
  eventChar = service->createCharacteristic(
      EVENT_CHAR_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
#ifdef CONFIG_BLUEDROID_ENABLED
  eventChar->addDescriptor(new BLE2902());
#endif
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SETUP_SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

// Wi-Fi list cache: the detector scans in the background while in setup mode,
// so when the app asks, the list is sent immediately instead of after a
// 2–4 s blocking scan.
struct CachedNetwork { String ssid; int rssi; bool secure; };
const int MAX_NETWORKS = 20;
const unsigned long SCAN_CACHE_MAX_AGE = 30000;
CachedNetwork cachedNetworks[MAX_NETWORKS];
int cachedCount = 0;
unsigned long cachedAt = 0;
bool backgroundScanRunning = false;

// Copies finished scan results into the cache (deduplicated, strongest first
// as reported by the radio).
void storeScanResults(int found) {
  cachedCount = 0;
  for (int i = 0; i < found && cachedCount < MAX_NETWORKS; i++) {
    String ssid = WiFi.SSID(i);
    if (ssid.length() == 0) continue;  // hidden network
    bool duplicate = false;
    for (int j = 0; j < cachedCount; j++) {
      if (cachedNetworks[j].ssid == ssid) { duplicate = true; break; }
    }
    if (duplicate) continue;
    cachedNetworks[cachedCount++] = {ssid, WiFi.RSSI(i), WiFi.encryptionType(i) != WIFI_AUTH_OPEN};
  }
  WiFi.scanDelete();
  cachedAt = millis();
}

// Called every loop() in setup mode: keeps the cache fresh in the background.
void backgroundWifiScanTick() {
  if (provState != PROV_IDLE) return;
  if (backgroundScanRunning) {
    int found = WiFi.scanComplete();
    if (found >= 0) {
      storeScanResults(found);
      backgroundScanRunning = false;
    } else if (found == WIFI_SCAN_FAILED) {
      backgroundScanRunning = false;
    }
  } else if (cachedAt == 0 || millis() - cachedAt > SCAN_CACHE_MAX_AGE) {
    backgroundScanRunning = WiFi.scanNetworks(true) == WIFI_SCAN_RUNNING;  // async
  }
}

void scanWifiNetworks() {
  if (provState != PROV_IDLE) return;
  bool fresh = cachedAt != 0 && millis() - cachedAt <= SCAN_CACHE_MAX_AGE;
  if (!fresh) {
    Serial.println("Bluetooth: scanning Wi-Fi networks for the app...");
    if (backgroundScanRunning) {
      // Let the scan already in progress finish rather than start another.
      unsigned long start = millis();
      while (WiFi.scanComplete() == WIFI_SCAN_RUNNING && millis() - start < 8000) delay(50);
      int found = WiFi.scanComplete();
      backgroundScanRunning = false;
      if (found >= 0) storeScanResults(found);
    }
    if (cachedAt == 0 || millis() - cachedAt > SCAN_CACHE_MAX_AGE) {
      WiFi.disconnect();
      storeScanResults(WiFi.scanNetworks());
    }
  }

  for (int i = 0; i < cachedCount; i++) {
    JsonDocument doc;
    doc["type"] = "network";
    doc["ssid"] = cachedNetworks[i].ssid;
    doc["rssi"] = cachedNetworks[i].rssi;
    doc["secure"] = cachedNetworks[i].secure;
    sendEvent(doc);
  }
  JsonDocument done;
  done["type"] = "scan_done";
  done["count"] = cachedCount;
  sendEvent(done);
  Serial.print("Bluetooth: sent ");
  Serial.print(cachedCount);
  Serial.println(fresh ? " Wi-Fi networks (from background scan)" : " Wi-Fi networks");
}

void startProvisioning(JsonDocument& doc) {
  provSsid = (const char*)(doc["ssid"] | "");
  provPass = (const char*)(doc["password"] | "");
  provCode = (const char*)(doc["code"] | "");
  provServer = normalizeServer((const char*)(doc["server"] | ""));
  provCode.trim();
  provCode.toUpperCase();
  if (provSsid.length() == 0 || provCode.length() == 0 || provServer.length() == 0) {
    sendStatus("failed", "bad_request");
    return;
  }

  Serial.print("Bluetooth: connecting to Wi-Fi \"");
  Serial.print(provSsid);
  Serial.println("\"...");
  authFailures = 0;
  lastDisconnectReason = 0;
  WiFi.disconnect();
  WiFi.begin(provSsid.c_str(), provPass.c_str());
  provState = PROV_CONNECTING;
  provStartedAt = millis();
  sendStatus("connecting_wifi");
}

// Three short beeps + LED flashes so the user can tell which physical device
// the app is connected to when several are being set up.
void identifyBeep() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, HIGH);
    ledcWriteTone(BUZZER_PIN, ALARM_PITCH);
    ledcWrite(BUZZER_PIN, 128);
    delay(120);
    digitalWrite(LED_PIN, LOW);
    ledcWrite(BUZZER_PIN, 0);
    ledcWriteTone(BUZZER_PIN, 0);
    delay(120);
  }
}

void handleCommand(const String& json) {
  JsonDocument doc;
  if (deserializeJson(doc, json)) {
    sendStatus("failed", "bad_request");
    return;
  }
  const char* cmd = doc["cmd"] | "";
  if (strcmp(cmd, "hello") == 0) {
    JsonDocument hello;
    hello["type"] = "hello";
    hello["device"] = deviceName;
    hello["fw"] = FW_VERSION;
    sendEvent(hello);
    if (!alarmActive) identifyBeep();
  } else if (strcmp(cmd, "identify") == 0) {
    if (!alarmActive) identifyBeep();  // never interrupt a real alarm
  } else if (strcmp(cmd, "scan") == 0) {
    scanWifiNetworks();
  } else if (strcmp(cmd, "provision") == 0) {
    startProvisioning(doc);
  }
}

// Runs every loop() in setup mode: connect to Wi-Fi; once that works, save
// the settings and restart into normal mode.
//
// The server is NOT contacted here: an HTTPS (TLS) handshake needs ~45 KB of
// RAM, which isn't available while Bluetooth is also running. After the
// restart Bluetooth is off, the detector uploads over HTTPS normally, and the
// app confirms setup by waiting for that first reading to reach the server.
void provisioningTick() {
  if (provState == PROV_CONNECTING) {
    if (WiFi.status() == WL_CONNECTED) {
      JsonDocument doc;
      doc["type"] = "status";
      doc["state"] = "wifi_connected";
      doc["ip"] = WiFi.localIP().toString();
      sendEvent(doc);
      provState = PROV_CHECKING;
      return;
    }
    const char* reason = nullptr;
    unsigned long elapsed = millis() - provStartedAt;
    if (authFailures >= 2) {
      reason = "wrong_password";
    } else if (elapsed > WIFI_SETUP_TIMEOUT) {
      if (authFailures > 0) reason = "wrong_password";
      else if (lastDisconnectReason == WIFI_REASON_NO_AP_FOUND) reason = "network_not_found";
      else reason = "wifi_timeout";
    }
    if (reason) {
      Serial.print("Bluetooth: Wi-Fi failed (");
      Serial.print(reason);
      Serial.println(")");
      WiFi.disconnect();
      provState = PROV_IDLE;
      sendStatus("failed", reason);
    }
  } else if (provState == PROV_CHECKING) {
    saveSettings();
    JsonDocument doc;
    doc["type"] = "status";
    doc["state"] = "done";
    sendEvent(doc);
    Serial.println("Setup saved — restarting in normal mode to connect to the server...");
    delay(1500);  // let the "done" message reach the app
    ESP.restart();
  }
}

void onWiFiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
  if (event != ARDUINO_EVENT_WIFI_STA_DISCONNECTED) return;
  uint8_t reason = info.wifi_sta_disconnected.reason;
  lastDisconnectReason = reason;
  if (reason == WIFI_REASON_AUTH_FAIL || reason == WIFI_REASON_AUTH_EXPIRE ||
      reason == WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT || reason == WIFI_REASON_HANDSHAKE_TIMEOUT) {
    authFailures = authFailures + 1;
  }
}

void blinkSetupLed() {
  if (alarmActive) return;  // alarm keeps the LED solid on
  if (millis() - lastBlinkAt >= SETUP_BLINK_MS) {
    lastBlinkAt = millis();
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
  }
}

void reportWifiChanges() {
  bool connected = WiFi.status() == WL_CONNECTED;
  if (connected == wasWifiConnected) return;
  wasWifiConnected = connected;
  if (connected) {
    Serial.print("WiFi connected: ");
    Serial.println(WiFi.localIP());
    // HTTPS certificates have validity dates; give the TLS library real time.
    configTime(0, 0, "pool.ntp.org", "time.google.com");
  } else {
    Serial.println("WiFi disconnected — reconnecting automatically...");
  }
}

void connectionWatchdog() {
  unsigned long now = millis();

  if (WiFi.status() == WL_CONNECTED) {
    wifiLostAt = 0;
  } else if (wifiLostAt == 0) {
    wifiLostAt = now;
  } else if (now - wifiLostAt >= WIFI_RETRY_MS) {
    Serial.println("WiFi still down — retrying the connection...");
    WiFi.disconnect();
    WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
    wifiLostAt = now;
  }

  if (!alarmActive && now - lastServerReplyAt >= NO_SERVER_RESTART_MS) {
    Serial.println("No reply from the server for 10 minutes — restarting...");
    delay(100);
    ESP.restart();
  }
}

// ==================== UPLOAD ====================
void sendReading(int gasValue, float temperature, bool validTemperature,
                 float humidity, bool validHumidity) {
  if (setupMode) {
    Serial.println("Upload: skipped (setup mode — open the NotiFire app and tap Add detector)");
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Upload: skipped (no WiFi)");
    return;
  }

  JsonDocument doc;
  doc["gas"] = gasValue;
  if (validTemperature) doc["temperature"] = temperature;
  else doc["temperature"] = nullptr;
  if (validHumidity) doc["humidity"] = humidity;
  else doc["humidity"] = nullptr;

  String body;
  serializeJson(doc, body);

  if (!beginRequest(serverUrl + INGEST_PATH, HTTP_TIMEOUT_MS)) return;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Detector-Code", detectorCode);

  int code = http.POST(body);
  if (code > 0) lastServerReplyAt = millis();
  if (code == 201) {
    // Backend echoes this detector's app-controlled MQ-5 toggle.
    JsonDocument resp;
    if (deserializeJson(resp, http.getString()) == DeserializationError::Ok) {
      bool enabled = resp["mq5_enabled"] | true;
      if (enabled != mq5Enabled) {
        mq5Enabled = enabled;
        Serial.print("MQ-5 toggled from app: ");
        Serial.println(mq5Enabled ? "ON" : "OFF");
      }
    }
    Serial.println("Upload: OK");
  } else if (code == 403) {
    Serial.println("Upload: this detector was deleted in the app. Hold BOOT 5 s and set it up again.");
  } else if (code == 429) {
    Serial.println("Upload: server rate limit reached — slowing down.");
  } else {
    Serial.print("Upload: failed (HTTP ");
    Serial.print(code);
    Serial.print(") to ");
    Serial.println(serverUrl);
    if (code < 0 && serverUrl.startsWith("https://")) {
      char tlsError[120];
      int err = secureClient.lastError(tlsError, sizeof(tlsError));
      Serial.printf("        TLS error %d: %s | free memory: %u bytes\n",
                    err, tlsError, (unsigned)ESP.getFreeHeap());
    }
  }
  http.end();
  // Don't reuse a connection that just failed; the next upload opens a fresh one.
  if (code < 0) {
    secureClient.stop();
    plainClient.stop();
  }
}

// ==================== SETUP ====================
void setup() {
  Serial.begin(115200);

  pinMode(MQ5PIN, INPUT);
  pinMode(LED_PIN, OUTPUT);
  pinMode(RESET_PIN, INPUT_PULLUP);

  // Keep LED OFF during startup
  digitalWrite(LED_PIN, LOW);

  // Initialize buzzer PWM (ESP32 Arduino Core 3.x)
  ledcAttach(BUZZER_PIN, ALARM_PITCH, PWM_RESOLUTION);
  ledcWrite(BUZZER_PIN, 0);

  // HTTPS: verify the server's certificate against the bundled roots.
  secureClient.setCACert(ROOT_CA_BUNDLE);
  secureClient.setHandshakeTimeout(15);  // seconds

  // Start DHT22
  dht.begin();

  uint64_t mac = ESP.getEfuseMac();
  char name[20];
  snprintf(name, sizeof(name), "NotiFire-%04X", (uint16_t)(mac >> 32));
  deviceName = name;

  Serial.println();
  Serial.println("==========================================");
  Serial.println(" NOTIFIRE — ESP32 GAS & ENVIRONMENT MONITOR");
  Serial.print(" Firmware ");
  Serial.println(FW_VERSION);
  Serial.println("==========================================");

  loadSettings();
  WiFi.onEvent(onWiFiEvent);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);

  setupMode = wifiSsid.length() == 0 || detectorCode.length() == 0 || serverUrl.length() == 0;
  if (setupMode) {
    startBluetoothSetup();
    Serial.println("SETUP MODE (LED blinking).");
    Serial.println("Open the NotiFire app and tap \"Add detector\" — it will find this device:");
    Serial.print("  Bluetooth name: ");
    Serial.println(deviceName);
  } else {
    Serial.print("Connecting to WiFi \"");
    Serial.print(wifiSsid);
    Serial.println("\"...");
    WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  }

  Serial.println("Warming up MQ-5 for 20 seconds before monitoring...");
}

// ==================== MAIN LOOP ====================
void loop() {
  checkResetButton();

  if (setupMode) {
    if (commandPending) {
      String command = pendingCommand;
      commandPending = false;
      handleCommand(command);
    }
    provisioningTick();
    backgroundWifiScanTick();
    blinkSetupLed();
  } else {
    reportWifiChanges();
    connectionWatchdog();
  }

  unsigned long currentTime = millis();

  if (!warmupDone) {
    if (currentTime < WARMUP_MS) return;
    warmupDone = true;
    Serial.println("Warm-up completed. Monitoring sensors...");
  }

  // Read sensors every 2 seconds
  if (currentTime - lastReadTime < SENSOR_INTERVAL) {
    return;
  }

  lastReadTime = currentTime;

  // ==================== READ SENSORS ====================
  int gasValue = analogRead(MQ5PIN);
  float temperature = dht.readTemperature();
  float humidity = dht.readHumidity();

  Serial.println("\n-------- SENSOR DATA --------");

  Serial.print("Gas Level: ");
  Serial.print(gasValue);
  Serial.println(mq5Enabled ? "" : " (MQ-5 disabled from app)");

  bool validTemperature = !isnan(temperature);
  bool validHumidity = !isnan(humidity);

  if (validTemperature) {
    Serial.print("Temperature: ");
    Serial.print(temperature, 1);
    Serial.println(" C");
  } else {
    Serial.println("Temperature: SENSOR ERROR");
  }

  if (validHumidity) {
    Serial.print("Humidity: ");
    Serial.print(humidity, 1);
    Serial.println(" %");
  } else {
    Serial.println("Humidity: SENSOR ERROR");
  }

  // ==================== CHECK THRESHOLDS ====================
  bool gasAlert = mq5Enabled && gasValue > GAS_THRESHOLD;

  bool temperatureAlert =
      validTemperature && temperature > TEMP_THRESHOLD;

  bool humidityAlert =
      validHumidity && humidity > HIGH_HUMID_THRESHOLD;

  // Trigger if ANY valid sensor reaches its threshold, and keep sounding
  // for ALARM_HOLD_MS after the last such reading.
  bool overThreshold = gasAlert || temperatureAlert || humidityAlert;
  if (overThreshold) lastTriggerAt = currentTime;
  bool holding = !overThreshold && lastTriggerAt != 0 &&
                 currentTime - lastTriggerAt < ALARM_HOLD_MS;
  bool alarmTriggered = overThreshold || holding;
  alarmActive = alarmTriggered;

  // ==================== CONTROL LED & BUZZER ====================
  if (alarmTriggered) {
    digitalWrite(LED_PIN, HIGH);

    // Continuous buzzer tone
    ledcWriteTone(BUZZER_PIN, ALARM_PITCH);
    ledcWrite(BUZZER_PIN, 128);

    Serial.println("Status: ALARM");
    Serial.println("!!! ALERT ACTIVATED !!!");

    if (gasAlert) {
      Serial.println("Reason: High gas reading.");
    }

    if (temperatureAlert) {
      Serial.println("Reason: High temperature.");
    }

    if (humidityAlert) {
      Serial.println("Reason: High humidity.");
    }

    if (holding) {
      Serial.print("Readings are back to normal; alarm stops in ");
      Serial.print((ALARM_HOLD_MS - (currentTime - lastTriggerAt) + 999) / 1000);
      Serial.println(" s.");
    }

    Serial.println("LED: ON");
    Serial.println("BUZZER: ON");

  } else {
    if (!setupMode) digitalWrite(LED_PIN, LOW);  // setup mode keeps blinking

    // Stop buzzer
    ledcWrite(BUZZER_PIN, 0);
    ledcWriteTone(BUZZER_PIN, 0);

    Serial.println("Status: NORMAL");
    Serial.println(setupMode ? "LED: BLINKING (setup mode)" : "LED: OFF");
    Serial.println("BUZZER: OFF");
  }

  // ==================== UPLOAD TO BACKEND ====================
  // Done after the alarm is set, so a slow network never delays the buzzer.
  // Every UPLOAD_INTERVAL, or right away when the alarm turns on/off so the
  // app and push notification follow within seconds.
  bool alarmChanged = alarmTriggered != lastUploadedAlarm;
  if (alarmChanged || lastUploadAt == 0 || currentTime - lastUploadAt >= UPLOAD_INTERVAL) {
    lastUploadAt = currentTime;
    lastUploadedAlarm = alarmTriggered;
    sendReading(gasValue, temperature, validTemperature, humidity, validHumidity);
  }

  Serial.println("-----------------------------");
}
