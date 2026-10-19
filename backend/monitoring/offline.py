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


def prune_old_readings() -> int:
    """Delete raw readings older than NOTIFIRE_READING_RETENTION_DAYS so the
    database stays within Supabase's free 500 MB (a detector stores ~14,000
    readings a day). Alert history is kept: each alert stores its own copy of
    the readings at that moment. Returns how many readings were deleted."""
    from .models import SensorReading

    cutoff = timezone.now() - timedelta(days=settings.NOTIFIRE_READING_RETENTION_DAYS)
    deleted, _ = SensorReading.objects.filter(created_at__lt=cutoff).delete()
    return deleted


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
