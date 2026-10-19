"""
Alert owners when a detector stops reporting.

    python manage.py check_offline

See monitoring/offline.py. In production on Render's free tier, an external
pinger calls /api/internal/check-offline/ instead (cron jobs aren't free).
"""
from django.core.management.base import BaseCommand

from monitoring import notifications
from monitoring.offline import prune_old_readings, run_offline_check


class Command(BaseCommand):
    help = "Send push notifications for detectors that went offline; prune old readings."

    def handle(self, *args, **options):
        count = run_offline_check()
        pruned = prune_old_readings()
        # Pushes go out on a background pool; give it time before exiting.
        notifications.wait_for_pending(timeout=30)
        self.stdout.write(f"Offline check: {count} detector(s) newly offline. "
                          f"Deleted {pruned} old reading(s).")
