"""
Firebase integration (optional).

Credentials (service-account JSON) come from either:
  FIREBASE_CREDENTIALS_JSON  the JSON itself (handy on Render), or
  FIREBASE_CREDENTIALS       a path to the JSON file.

With credentials set, push notifications are sent through Firebase Cloud
Messaging (see notifications.py). If FIREBASE_DATABASE_URL is also set,
readings/logs are mirrored to Realtime Database:

    /notifire/detectors/<id>/latest          -> latest sensor reading + level
    /notifire/detectors/<id>/state           -> detector state (mq5_enabled)
    /notifire/detectors/<id>/logs/<push-id>  -> WARNING / DANGER detection logs

Everything works without Firebase — calls are skipped when not configured.
"""
import json
import logging
import threading

from django.conf import settings

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_app = None
_initialised = False


def get_app():
    """Lazily initialise the Firebase app. Returns None when not configured."""
    global _app, _initialised
    if _initialised:
        return _app
    with _lock:
        if _initialised:
            return _app
        _initialised = True
        raw = settings.FIREBASE_CREDENTIALS_JSON
        path = settings.FIREBASE_CREDENTIALS
        if not raw and not path:
            return None
        try:
            import firebase_admin
            from firebase_admin import credentials

            cred = credentials.Certificate(json.loads(raw) if raw else path)
            options = {"databaseURL": settings.FIREBASE_DATABASE_URL} if settings.FIREBASE_DATABASE_URL else None
            _app = firebase_admin.initialize_app(cred, options)
            logger.info("Firebase enabled (push%s).",
                        " + Realtime Database mirror" if options else "")
        except Exception as exc:  # noqa: BLE001
            logger.error("Firebase disabled — bad credentials: %s", exc)
            _app = None
    return _app


def _mirror(path: str, payload: dict, push: bool = False) -> None:
    if not settings.FIREBASE_DATABASE_URL or get_app() is None:
        return
    try:
        from firebase_admin import db

        ref = db.reference(path)
        ref.push(payload) if push else ref.set(payload)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Firebase mirror to %s failed: %s", path, exc)


def push_latest(detector_id: int, payload: dict) -> None:
    _mirror(f"/notifire/detectors/{detector_id}/latest", payload)


def push_detector(detector_id: int, payload: dict) -> None:
    _mirror(f"/notifire/detectors/{detector_id}/state", payload)


def push_log(detector_id: int, payload: dict) -> None:
    _mirror(f"/notifire/detectors/{detector_id}/logs", payload, push=True)
