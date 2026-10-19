import secrets

from django.conf import settings
from django.db import models

# Unambiguous characters (no 0/O, 1/I/L) so codes are easy to type on the
# ESP32 setup page.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def generate_detector_code() -> str:
    """e.g. NF-7K3Q-9XPA — 8 random chars (~40 bits), unique per detector."""
    while True:
        raw = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
        code = f"NF-{raw[:4]}-{raw[4:]}"
        if not Detector.objects.filter(code=code).exists():
            return code


class Profile(models.Model):
    """Per-user account state and notification preferences."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                related_name="profile")
    email_verified = models.BooleanField(default=False)
    notify_danger = models.BooleanField(default=True)
    notify_warning = models.BooleanField(default=False)  # humid climates trip WARNING often
    notify_offline = models.BooleanField(default=True)

    def __str__(self):
        return f"Profile({self.user.username}, verified={self.email_verified})"


class EmailCode(models.Model):
    """One-time 6-digit code emailed to the user. Only a keyed hash is stored."""

    class Purpose(models.TextChoices):
        VERIFY = "verify", "Verify email"
        RESET = "reset", "Reset password"
        CHANGE_EMAIL = "change_email", "Change email"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                             related_name="email_codes")
    purpose = models.CharField(max_length=16, choices=Purpose.choices)
    new_email = models.EmailField(blank=True)  # target address for CHANGE_EMAIL
    code_hash = models.CharField(max_length=64)
    attempts = models.PositiveSmallIntegerField(default=0)
    used = models.BooleanField(default=False)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "purpose", "-created_at"],
                                name="emailcode_user_purpose_idx")]


class PushDevice(models.Model):
    """A phone that receives push notifications (Firebase Cloud Messaging)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                             related_name="push_devices")
    token = models.CharField(max_length=512, unique=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"PushDevice({self.user_id}, …{self.token[-8:]})"


class Level(models.TextChoices):
    SAFE = "SAFE", "Safe"
    WARNING = "WARNING", "Warning"
    DANGER = "DANGER", "Danger"


class Detector(models.Model):
    """One ESP32 unit, owned by a user. The app sends `code` to the ESP32 over
    Bluetooth during setup; the ESP32 then identifies itself with it."""

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="detectors"
    )
    room = models.CharField(max_length=60)   # e.g. "Bedroom"
    name = models.CharField(max_length=60)   # e.g. "Bedroom Detector" (defaults from room)
    code = models.CharField(max_length=16, unique=True, default=generate_detector_code, editable=False)
    mq5_enabled = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    # Set when the owner was told this detector went offline; cleared when
    # it reports again, so each outage triggers one alert.
    offline_notified_at = models.DateTimeField(null=True, blank=True)
    # Level of the last DANGER/WARNING alert pushed to the owner; when the
    # detector reads SAFE again we push "back to normal" and clear it.
    alert_level = models.CharField(max_length=10, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]

    def save(self, *args, **kwargs):
        self.room = self.room.strip()
        self.name = self.name.strip() or f"{self.room} Detector"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} — {self.room} ({self.code})"


class DetectorMember(models.Model):
    """Someone in the household the owner shared a detector with. They see
    its readings and history and get its alerts; only the owner can change
    or delete it.

    Added by email. `user` is set straight away when that email already has
    a verified account, otherwise once someone registers and verifies it
    (see access.link_pending_invites) — so access only ever goes to whoever
    proved they own the address."""

    detector = models.ForeignKey(Detector, on_delete=models.CASCADE, related_name="members")
    email = models.EmailField()  # lowercase
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                             null=True, blank=True, related_name="shared_detectors")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
        constraints = [
            models.UniqueConstraint(fields=["detector", "email"], name="member_detector_email_uniq"),
        ]
        indexes = [models.Index(fields=["email"], name="member_email_idx")]

    def __str__(self):
        return f"{self.email} → {self.detector_id}" + ("" if self.user_id else " (pending)")


class SensorReading(models.Model):
    """A single reading pushed by an ESP32 detector."""

    detector = models.ForeignKey(Detector, on_delete=models.CASCADE, related_name="readings")
    gas = models.FloatField(null=True, blank=True)          # raw MQ-5 ADC 0–4095; null when MQ-5 disabled
    temperature = models.FloatField(null=True, blank=True)  # °C (DHT22); null on sensor error
    humidity = models.FloatField(null=True, blank=True)     # %RH (DHT22); null on sensor error
    mq5_enabled = models.BooleanField(default=True)
    level = models.CharField(max_length=10, choices=Level.choices, default=Level.SAFE)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.created_at:%H:%M:%S}] {self.detector_id} {self.level} gas={self.gas} t={self.temperature} h={self.humidity}"


class DetectionLog(models.Model):
    """History log — WARNING and DANGER events only."""

    detector = models.ForeignKey(Detector, on_delete=models.CASCADE, related_name="logs")
    level = models.CharField(max_length=10, choices=Level.choices)
    message = models.CharField(max_length=255)
    gas = models.FloatField(null=True, blank=True)
    temperature = models.FloatField(null=True, blank=True)
    humidity = models.FloatField(null=True, blank=True)
    reading = models.ForeignKey(
        SensorReading, null=True, blank=True, on_delete=models.SET_NULL, related_name="logs"
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.created_at:%Y-%m-%d %H:%M:%S}] {self.level}: {self.message}"
