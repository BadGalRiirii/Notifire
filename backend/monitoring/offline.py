"""
Offline detection: alert owners when a detector stops reporting.

A detector that was online and has been silent longer than
NOTIFIRE_OFFLINE_ALERT_MINUTES triggers one "offline" push; it is re-armed
when the detector reports again (see views.ingest_reading).

Triggered either by `python manage.py check_offline` (e.g. a scheduler) or by
an external pinger calling /api/internal/check-offline/ — on Render's free
tier that same ping also keeps the server from sleeping.
"""
from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from . import notifications
from .models import Detector


def run_offline_check() -> int:
    """Notify about newly offline detectors. Returns how many."""
    cutoff = timezone.now() - timedelta(minutes=settings.NOTIFIRE_OFFLINE_ALERT_MINUTES)
    stale = (Detector.objects.select_related("owner__profile")
             .filter(last_seen_at__lt=cutoff, offline_notified_at__isnull=True))
    count = 0
    for detector in stale:
        notifications.notify_offline(detector)
        detector.offline_notified_at = timezone.now()
        detector.save(update_fields=["offline_notified_at"])
        count += 1
    return count
