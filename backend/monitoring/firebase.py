"""
Optional Firebase Realtime Database mirroring.

If settings.FIREBASE_CREDENTIALS (service account JSON path) and
settings.FIREBASE_DATABASE_URL are configured, every reading and detection
log is mirrored to Firebase so the mobile app (or future FCM push
notifications) can consume it directly:

    /notifire/latest          -> latest sensor reading + level
    /notifire/device          -> device state (mq5_enabled)
    /notifire/logs/<push-id>  -> WARNING / DANGER detection logs

The whole system works without Firebase — mirroring is silently skipped when
not configured, so you can develop fully locally with SQLite.
"""
import logging

from django.conf import settings

logger = logging.getLogger(__name__)

_app = None
_available = None


def _init() -> bool:
    """Lazily initialise the Firebase app. Returns True when usable."""
    global _app, _available
    if _available is not None:
        return _available
    if not settings.FIREBASE_CREDENTIALS or not settings.FIREBASE_DATABASE_URL:
        _available = False
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS)
        _app = firebase_admin.initialize_app(
            cred, {"databaseURL": settings.FIREBASE_DATABASE_URL}
        )
        _available = True
        logger.info("Firebase mirroring enabled.")
    except Exception as exc:  # noqa: BLE001
        logger.warning("Firebase disabled (%s). Running local-only.", exc)
        _available = False
    return _available


def push_latest(payload: dict) -> None:
    if not _init():
        return
    try:
        from firebase_admin import db

        db.reference("/notifire/latest").set(payload)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Firebase push_latest failed: %s", exc)


def push_device_state(payload: dict) -> None:
    if not _init():
        return
    try:
        from firebase_admin import db

        db.reference("/notifire/device").set(payload)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Firebase push_device_state failed: %s", exc)


def push_log(payload: dict) -> None:
    if not _init():
        return
    try:
        from firebase_admin import db

        db.reference("/notifire/logs").push(payload)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Firebase push_log failed: %s", exc)
