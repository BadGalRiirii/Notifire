"""
Alert owners when a detector stops reporting.

    python manage.py check_offline

See monitoring/offline.py. In production on Render's free tier, an external
pinger calls /api/internal/check-offline/ instead (cron jobs aren't free).
"""
from django.core.management.base import BaseCommand

from monitoring import notifications
from monitoring.offline import run_offline_check


class Command(BaseCommand):
    help = "Send a push notification for detectors that went offline."

    def handle(self, *args, **options):
        count = run_offline_check()
        # Pushes go out on a background pool; give it time before exiting.
        notifications.wait_for_pending(timeout=30)
        self.stdout.write(f"Offline check: {count} detector(s) newly offline.")
