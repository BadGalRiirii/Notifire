"""
Alert owners when a detector stops reporting.

    python manage.py check_offline

Run every few minutes (Render cron job). A detector that was online and has
been silent longer than NOTIFIRE_OFFLINE_ALERT_MINUTES triggers one "offline"
push; it is re-armed when the detector reports again (see ingest_reading).
"""
from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from monitoring import notifications
from monitoring.models import Detector


class Command(BaseCommand):
    help = "Send a push notification for detectors that went offline."

    def handle(self, *args, **options):
        cutoff = timezone.now() - timedelta(minutes=settings.NOTIFIRE_OFFLINE_ALERT_MINUTES)
        stale = (Detector.objects.select_related("owner__profile")
                 .filter(last_seen_at__lt=cutoff, offline_notified_at__isnull=True))
        count = 0
        for detector in stale:
            notifications.notify_offline(detector)
            detector.offline_notified_at = timezone.now()
            detector.save(update_fields=["offline_notified_at"])
            count += 1
        # Pushes go out on a background pool; give it time before exiting.
        notifications.wait_for_pending(timeout=30)
        self.stdout.write(f"Offline check: {count} detector(s) newly offline.")
