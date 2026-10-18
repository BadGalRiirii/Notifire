"""
Threshold classification — mirrors the alarm logic flashed on the ESP32 so
the app and the on-device buzzer always agree:

    DANGER  if MQ-5 raw > 1500  OR  temp > 40°C  OR  humidity > 85 %RH
    WARNING if gas or temperature are approaching those levels
    SAFE    otherwise

Humidity has no WARNING band: 75–84 %RH is a normal day in Cagayan de Oro,
and humidity alone isn't a sign of fire, so it only counts at the device's
danger level.

The MQ-5 value is the raw 12-bit ADC reading (0–4095), not ppm.

When the MQ-5 sensor is toggled OFF from the app, gas is excluded from the
decision (temperature/humidity detection stays active). A DHT22 value that
is missing (sensor error) is skipped, same as on the device.

Messages are shown to users (app history, push notifications): keep them
short and plain.
"""
from dataclasses import dataclass
from typing import Optional

from django.conf import settings


@dataclass
class Classification:
    level: str            # SAFE | WARNING | DANGER
    reasons: list[str]

    @property
    def message(self) -> str:
        return "; ".join(self.reasons) if self.reasons else "Normal conditions"


def classify(gas: Optional[float], temperature: Optional[float], humidity: Optional[float],
             mq5_enabled: bool = True) -> Classification:
    danger_reasons: list[str] = []
    warning_reasons: list[str] = []

    if mq5_enabled and gas is not None:
        if gas > settings.NOTIFIRE_GAS_DANGER:
            danger_reasons.append(f"Smoke or gas detected (level {gas:.0f})")
        elif gas > settings.NOTIFIRE_GAS_WARNING:
            warning_reasons.append(f"Smoke or gas is rising (level {gas:.0f})")

    if temperature is not None:
        if temperature > settings.NOTIFIRE_TEMP_DANGER:
            danger_reasons.append(f"Very high temperature ({temperature:.1f}°C)")
        elif temperature >= settings.NOTIFIRE_TEMP_WARNING:
            warning_reasons.append(f"Temperature is rising ({temperature:.1f}°C)")

    if humidity is not None and humidity > settings.NOTIFIRE_HUM_DANGER:
        danger_reasons.append(f"Very high humidity ({humidity:.1f}%)")

    if danger_reasons:
        return Classification("DANGER", danger_reasons)
    if warning_reasons:
        return Classification("WARNING", warning_reasons)
    return Classification("SAFE", [])
