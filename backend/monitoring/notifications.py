"""
Push notifications via Firebase Cloud Messaging, to the phones of everyone
with access to the detector: its owner and the household members it was
shared with (each person's own notification settings apply).

Who gets what is decided synchronously (cheap DB reads); the network send to
Google happens on a small background thread pool so an ESP32's upload is never
delayed by FCM. Tokens Google reports as dead are deleted.
"""
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

from django.db import close_old_connections
from django.utils import timezone

from . import access, firebase
from .models import DetectionLog, Detector, Level, PushDevice

logger = logging.getLogger(__name__)

# Android notification channels (created by the app; ids must match).
CHANNEL_ALARMS = "notifire_alarms"   # DANGER — max importance, alarm sound
CHANNEL_ALERTS = "notifire_alerts"   # WARNING / offline — high importance

_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="fcm")


@dataclass
class Alert:
    title: str
    body: str
    channel: str
    detector_id: int
    kind: str  # DANGER | WARNING | SAFE | OFFLINE | ONLINE
    log_id: int | None = None  # the History entry that explains this alert


def deliver(tokens: list[str], alert: Alert) -> None:
    """Send now (runs on the pool). Replaced in tests."""
    if firebase.get_app() is None:
        logger.info("Push skipped (Firebase not configured): %s", alert.title)
        return
    from firebase_admin import messaging

    messages = [
        messaging.Message(
            token=token,
            notification=messaging.Notification(title=alert.title, body=alert.body),
            data={
                "detector_id": str(alert.detector_id),
                "kind": alert.kind,
                "log_id": str(alert.log_id or ""),
                "title": alert.title,  # also shown by the in-app pop-up
                "body": alert.body,
            },
            android=messaging.AndroidConfig(
                priority="high",
                ttl=600,  # a fire alert older than 10 minutes is not useful
                notification=messaging.AndroidNotification(
                    channel_id=alert.channel,
                    tag=f"detector-{alert.detector_id}",  # replaces, not stacks
                    default_sound=True,
                ),
            ),
        )
        for token in tokens
    ]
    try:
        result = messaging.send_each(messages)
    except Exception:  # noqa: BLE001
        logger.exception("FCM send failed for %s", alert.title)
        return

    dead = []
    for token, resp in zip(tokens, result.responses):
        if resp.success:
            continue
        if isinstance(resp.exception, (messaging.UnregisteredError,
                                       messaging.SenderIdMismatchError)):
            dead.append(token)
        else:
            logger.warning("FCM error for …%s: %s", token[-8:], resp.exception)
    if dead:
        try:
            PushDevice.objects.filter(token__in=dead).delete()
        finally:
            close_old_connections()
    logger.info("Push '%s' sent to %d/%d device(s)", alert.title,
                result.success_count, len(tokens))


_pending = set()


def _send(detector: Detector, alert: Alert, setting: str | None) -> bool:
    """Queue `alert` for everyone with access to `detector` whose profile
    has `setting` on (None: everyone). True if any phone was targeted."""
    users = [u for u in access.recipients(detector)
             if setting is None or getattr(u.profile, setting)]
    tokens = list(PushDevice.objects.filter(user__in=users).values_list("token", flat=True))
    if not tokens:
        return False
    future = _executor.submit(deliver, tokens, alert)
    _pending.add(future)
    future.add_done_callback(_pending.discard)
    return True


def wait_for_pending(timeout: float = 30) -> None:
    """Block until queued pushes finish (for short-lived processes like cron)."""
    from concurrent.futures import wait

    if _pending:
        wait(list(_pending), timeout=timeout)


def _clock(dt) -> str:
    return timezone.localtime(dt).strftime("%I:%M %p").lstrip("0")


def notify_detection(detector: Detector, log: DetectionLog) -> bool:
    """A new WARNING/DANGER log was recorded for this detector."""
    if log.level == Level.DANGER:
        alert = Alert(f"🔥 DANGER — {detector.room}",
                      f"{log.message}. Check the {detector.room.lower()} now!",
                      CHANNEL_ALARMS, detector.id, "DANGER", log.id)
        return _send(detector, alert, "notify_danger")
    alert = Alert(f"⚠️ Warning — {detector.room}", log.message,
                  CHANNEL_ALERTS, detector.id, "WARNING", log.id)
    return _send(detector, alert, "notify_warning")


def notify_back_to_normal(detector: Detector) -> bool:
    """Replaces the room's earlier alert in the notification tray (same tag),
    keeping what happened so the user still sees why they were alerted."""
    last = detector.logs.first()
    if last is not None:
        body = f"Earlier: {last.message} at {_clock(last.created_at)}. All readings are safe now."
    else:
        body = "All readings are safe now."
    alert = Alert(f"✅ {detector.room} is back to normal", body,
                  CHANNEL_ALERTS, detector.id, "SAFE", last.id if last else None)
    # Only to those who got the alert it replaces (same setting).
    setting = {"DANGER": "notify_danger", "WARNING": "notify_warning"}.get(detector.alert_level)
    return _send(detector, alert, setting)


def notify_offline(detector: Detector) -> bool:
    alert = Alert(f"📴 {detector.room} detector is offline",
                  f"{detector.name} stopped sending readings. Check its power and Wi-Fi.",
                  CHANNEL_ALERTS, detector.id, "OFFLINE")
    return _send(detector, alert, "notify_offline")


def notify_back_online(detector: Detector) -> bool:
    alert = Alert(f"✅ {detector.room} detector is back online",
                  f"{detector.name} is sending readings again.",
                  CHANNEL_ALERTS, detector.id, "ONLINE")
    return _send(detector, alert, "notify_offline")
