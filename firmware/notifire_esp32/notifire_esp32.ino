/*
 * NotiFire — Solar-Powered IoT-Based Smoke and Fire Detection System
 * ESP32 firmware (Grade 11 STEM 24 — Group 3)
 *
 * HARDWARE-READY PLACEHOLDER:
 * This sketch is structured for the real hardware (MQ-5 + DHT22 + buzzer
 * + LEDs) but works out-of-the-box even before parts arrive — flip
 * USE_FAKE_DATA to true and it sends simulated readings to the Django
 * backend, which is the exact same pipeline the app already consumes.
 *
 * Wiring (matches Chapter 3 hardware specifications):
 *   MQ-5 analog out  -> GPIO 34 (ADC1_CH6)
 *   DHT22 data       -> GPIO 4  (10k pull-up to 3.3V)
 *   Active buzzer    -> GPIO 25
 *   Red LED          -> GPIO 26 (220R series resistor)
 *   Green LED        -> GPIO 27 (220R series resistor)
 *
 * Libraries (Arduino IDE > Library Manager):
 *   - "DHT sensor library" by Adafruit (+ Adafruit Unified Sensor)
 *   - ArduinoJson by Benoit Blanchon
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// ============================ CONFIG =======================================
#define USE_FAKE_DATA true   // <— set to false once MQ-5 + DHT22 are wired

const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Django backend — your PC's LAN IP while prototyping
// (run: python manage.py runserver 0.0.0.0:8000)
const char* SERVER_URL = "http://192.168.1.100:8000/api/readings/ingest/";

const unsigned long SEND_INTERVAL_MS = 3000;

// Thresholds (Chapter 3 requirements analysis) — local alerts fire on-device
const float PPM_DANGER  = 1000.0;  // MQ-5 > 1000 ppm
const float TEMP_DANGER = 55.0;    // DHT22 >= 55 C (EN 54-5 Class C)
const float HUM_DANGER  = 85.0;    // >= 85 %RH

// Pins
const int PIN_MQ5_ANALOG = 34;
const int PIN_DHT        = 4;
const int PIN_BUZZER     = 25;
const int PIN_LED_RED    = 26;
const int PIN_LED_GREEN  = 27;

// ===========================================================================
#if !USE_FAKE_DATA
  #include <DHT.h>
  #define DHTTYPE DHT22
  DHT dht(PIN_DHT, DHTTYPE);
#endif

bool mq5Enabled = true;          // synced from the app via backend response
unsigned long lastSend = 0;

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  digitalWrite(PIN_LED_GREEN, HIGH);

#if !USE_FAKE_DATA
  dht.begin();
  // NOTE: MQ-5 needs >= 48h preheating per Winsen datasheet before analog
  // output is stable enough for threshold alarming (see Chapter 3).
#endif

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
}

float readPpm() {
#if USE_FAKE_DATA
  // Simulated MQ-5: baseline 150–400 ppm with occasional spikes
  static float ppm = 250;
  if (random(100) < 4) ppm += random(300, 900);      // random spike
  ppm += (250 - ppm) * 0.15 + random(-30, 31);        // drift to baseline
  return max(50.0f, ppm);
#else
  // Real MQ-5: map 12-bit ADC (0–4095 @ 3.3V) to an approximate ppm value.
  // Calibrate against the 2.5–4.0V @ 1000 ppm datasheet spec after the
  // 48-hour preheat and baseline (clean-air Rs) measurement.
  int raw = analogRead(PIN_MQ5_ANALOG);
  float voltage = raw * (3.3f / 4095.0f);
  float ppm = (voltage / 2.5f) * 1000.0f;             // placeholder mapping
  return ppm;
#endif
}

float readTemperature() {
#if USE_FAKE_DATA
  static float t = 28.0;
  t += (28.0 - t) * 0.1 + (random(-10, 11) / 10.0);
  return t;
#else
  float t = dht.readTemperature();
  return isnan(t) ? -1 : t;
#endif
}

float readHumidity() {
#if USE_FAKE_DATA
  static float h = 76.0;
  h += (76.0 - h) * 0.1 + (random(-15, 16) / 10.0);
  return constrain(h, 40, 100);
#else
  float h = dht.readHumidity();
  return isnan(h) ? -1 : h;
#endif
}

void setAlerts(bool danger) {
  digitalWrite(PIN_BUZZER, danger ? HIGH : LOW);
  digitalWrite(PIN_LED_RED, danger ? HIGH : LOW);
  digitalWrite(PIN_LED_GREEN, danger ? LOW : HIGH);
}

void loop() {
  if (millis() - lastSend < SEND_INTERVAL_MS) return;
  lastSend = millis();

  float ppm  = readPpm();
  float temp = readTemperature();
  float hum  = readHumidity();

  // Local alert logic — Chapter 3: smoke>1000ppm OR temp>=55C OR RH>=85%
  bool danger = (mq5Enabled && ppm > PPM_DANGER) ||
                (temp >= TEMP_DANGER) ||
                (hum >= HUM_DANGER);
  setAlerts(danger);

  Serial.printf("[%s] ppm=%.0f temp=%.1fC hum=%.0f%% mq5=%s\n",
                danger ? "DANGER" : "ok", ppm, temp, hum,
                mq5Enabled ? "on" : "off");

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost — reconnecting...");
    WiFi.reconnect();
    return;
  }

  HTTPClient http;
  http.begin(SERVER_URL);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  doc["ppm"] = ppm;
  doc["temperature"] = temp;
  doc["humidity"] = hum;
  doc["source"] = "esp32";
  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  if (code == 201) {
    // Backend echoes the app-controlled MQ-5 toggle — sync it locally.
    JsonDocument resp;
    if (deserializeJson(resp, http.getString()) == DeserializationError::Ok) {
      mq5Enabled = resp["mq5_enabled"] | true;
    }
  } else {
    Serial.printf("POST failed: %d\n", code);
  }
  http.end();
}
