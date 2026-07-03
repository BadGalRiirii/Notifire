"""
Fake ESP32 sensor simulator — run this while you don't have the hardware yet.

    python manage.py simulate_sensor                 # random realistic data
    python manage.py simulate_sensor --interval 2    # push every 2 seconds
    python manage.py simulate_sensor --scenario fire # force a fire event

It posts through the exact same ingest pipeline the real ESP32 will use, so
the app behaves identically once hardware arrives — you only change the
firmware's SERVER_URL.

Scenarios:
    normal   — CDO baseline: 25–32°C, 70–82%RH, 100–400 ppm, occasional random spikes
    warning  — hovers around warning thresholds
    fire     — smoke >1000 ppm + temp climbing past 55°C (DANGER)
    humidity — monsoon: humidity pushed toward/over 85%RH
"""
import random
import time

from django.core.management.base import BaseCommand
from django.test import Client


class Command(BaseCommand):
    help = "Simulate ESP32 sensor readings (fake data) into the ingest API."

    def add_arguments(self, parser):
        parser.add_argument("--interval", type=float, default=3.0,
                            help="Seconds between readings (default 3)")
        parser.add_argument("--scenario", type=str, default="normal",
                            choices=["normal", "warning", "fire", "humidity"])
        parser.add_argument("--count", type=int, default=0,
                            help="Number of readings to send (0 = run forever)")

    def handle(self, *args, **opts):
        client = Client()
        interval = opts["interval"]
        scenario = opts["scenario"]
        count = opts["count"]

        # slowly drifting baseline state
        temp = random.uniform(26.0, 29.0)
        hum = random.uniform(72.0, 78.0)
        ppm = random.uniform(150.0, 300.0)
        spike_ticks = 0  # ticks remaining in a random spike event

        self.stdout.write(self.style.SUCCESS(
            f"Simulating '{scenario}' scenario every {interval}s. Ctrl+C to stop."
        ))

        sent = 0
        try:
            while True:
                temp, hum, ppm, spike_ticks = self._step(
                    scenario, temp, hum, ppm, spike_ticks
                )

                payload = {
                    "ppm": round(ppm, 1),
                    "temperature": round(temp, 1),
                    "humidity": round(hum, 1),
                    "source": "simulator",
                }
                resp = client.post("/api/readings/ingest/", payload,
                                   content_type="application/json")
                if resp.status_code == 201:
                    body = resp.json()
                    level = body["reading"]["level"]
                    style = {
                        "SAFE": self.style.SUCCESS,
                        "WARNING": self.style.WARNING,
                        "DANGER": self.style.ERROR,
                    }[level]
                    self.stdout.write(style(
                        f"[{level:^7}] ppm={payload['ppm']:>7} "
                        f"temp={payload['temperature']:>5}°C hum={payload['humidity']:>5}%"
                        + ("  (MQ-5 OFF)" if not body["mq5_enabled"] else "")
                    ))
                else:
                    self.stdout.write(self.style.ERROR(f"HTTP {resp.status_code}: {resp.content}"))

                sent += 1
                if count and sent >= count:
                    break
                time.sleep(interval)
        except KeyboardInterrupt:
            self.stdout.write("\nSimulator stopped.")

    def _step(self, scenario, temp, hum, ppm, spike_ticks):
        """Advance the fake sensor state one tick."""
        if scenario == "fire":
            ppm = min(ppm + random.uniform(80, 200), 4000)
            temp = min(temp + random.uniform(1.0, 3.0), 90)
            hum += random.uniform(-0.5, 0.5)
        elif scenario == "warning":
            ppm += random.uniform(-40, 60)
            ppm = max(600, min(ppm, 980))
            temp += random.uniform(-0.5, 0.7)
            temp = max(42, min(temp, 52))
            hum += random.uniform(-1, 1)
        elif scenario == "humidity":
            hum = min(hum + random.uniform(0.3, 1.2), 95)
            temp += random.uniform(-0.3, 0.3)
            ppm += random.uniform(-20, 20)
        else:  # normal — with occasional random spikes so WARNING/DANGER logs appear
            if spike_ticks > 0:
                spike_ticks -= 1
                ppm = min(ppm + random.uniform(100, 300), 2500)
                temp = min(temp + random.uniform(0.5, 2.0), 70)
            else:
                if random.random() < 0.04:  # ~4% chance to start a spike
                    spike_ticks = random.randint(3, 8)
                # drift back to baseline
                ppm += (random.uniform(150, 300) - ppm) * 0.2 + random.uniform(-15, 15)
                temp += (random.uniform(26, 30) - temp) * 0.15 + random.uniform(-0.3, 0.3)
                hum += (random.uniform(72, 80) - hum) * 0.1 + random.uniform(-0.8, 0.8)

        ppm = max(50, ppm)
        hum = max(40, min(hum, 100))
        temp = max(20, temp)
        return temp, hum, ppm, spike_ticks
