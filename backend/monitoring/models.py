from django.db import models


class Level(models.TextChoices):
    SAFE = "SAFE", "Safe"
    WARNING = "WARNING", "Warning"
    DANGER = "DANGER", "Danger"


class DeviceState(models.Model):
    """Singleton row holding remotely-controllable device settings."""

    mq5_enabled = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Device state"

    def save(self, *args, **kwargs):
        self.pk = 1  # enforce singleton
        super().save(*args, **kwargs)

    @classmethod
    def load(cls) -> "DeviceState":
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj

    def __str__(self):
        return f"DeviceState(mq5_enabled={self.mq5_enabled})"


class SensorReading(models.Model):
    """A single reading pushed by the ESP32 (or the simulator)."""

    ppm = models.FloatField(null=True, blank=True)  # null when MQ-5 disabled
    temperature = models.FloatField()               # °C (DHT22)
    humidity = models.FloatField()                  # %RH (DHT22)
    mq5_enabled = models.BooleanField(default=True)
    level = models.CharField(max_length=10, choices=Level.choices, default=Level.SAFE)
    source = models.CharField(max_length=32, default="simulator")  # 'esp32' | 'simulator'
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.created_at:%H:%M:%S}] {self.level} ppm={self.ppm} t={self.temperature} h={self.humidity}"


class DetectionLog(models.Model):
    """History log — WARNING and DANGER events only."""

    level = models.CharField(max_length=10, choices=Level.choices)
    message = models.CharField(max_length=255)
    ppm = models.FloatField(null=True, blank=True)
    temperature = models.FloatField()
    humidity = models.FloatField()
    reading = models.ForeignKey(
        SensorReading, null=True, blank=True, on_delete=models.SET_NULL, related_name="logs"
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.created_at:%Y-%m-%d %H:%M:%S}] {self.level}: {self.message}"
