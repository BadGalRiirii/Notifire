"""
Threshold classification — implements the multi-sensor decision logic from
Chapter 3:

    DANGER  if MQ5 > 1000 ppm  OR  temp >= 55°C  OR  humidity >= 85 %RH
    WARNING if approaching those thresholds
    SAFE    otherwise

When the MQ-5 sensor is toggled OFF from the app, ppm is excluded from the
decision (temperature/humidity detection stays active).
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


def classify(ppm: Optional[float], temperature: float, humidity: float,
             mq5_enabled: bool = True) -> Classification:
    danger_reasons: list[str] = []
    warning_reasons: list[str] = []

    if mq5_enabled and ppm is not None:
        if ppm > settings.NOTIFIRE_PPM_DANGER:
            danger_reasons.append(f"Smoke/gas level {ppm:.0f} ppm exceeds {settings.NOTIFIRE_PPM_DANGER:.0f} ppm")
        elif ppm > settings.NOTIFIRE_PPM_WARNING:
            warning_reasons.append(f"Smoke/gas level rising ({ppm:.0f} ppm)")

    if temperature >= settings.NOTIFIRE_TEMP_DANGER:
        danger_reasons.append(f"Temperature {temperature:.1f}°C exceeds {settings.NOTIFIRE_TEMP_DANGER:.0f}°C")
    elif temperature >= settings.NOTIFIRE_TEMP_WARNING:
        warning_reasons.append(f"Temperature rising ({temperature:.1f}°C)")

    if humidity >= settings.NOTIFIRE_HUM_DANGER:
        danger_reasons.append(f"Humidity {humidity:.0f}%RH exceeds {settings.NOTIFIRE_HUM_DANGER:.0f}%RH")
    elif humidity >= settings.NOTIFIRE_HUM_WARNING:
        warning_reasons.append(f"Humidity rising ({humidity:.0f}%RH)")

    if danger_reasons:
        return Classification("DANGER", danger_reasons)
    if warning_reasons:
        return Classification("WARNING", warning_reasons)
    return Classification("SAFE", [])
