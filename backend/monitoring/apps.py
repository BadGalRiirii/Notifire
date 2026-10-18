from django.apps import AppConfig
from django.db.models.signals import post_migrate


def enable_rls_on_public_tables(using="default", **kwargs):
    """Supabase exposes the public schema through its Data API (anon key).
    Enabling RLS with no policies blocks that API; Django connects as the
    table owner, which bypasses RLS. Runs after every migrate so tables added
    later (e.g. authtoken) are covered too. No-op on SQLite."""
    from django.db import connections

    connection = connections[using]
    if connection.vendor != "postgresql":
        return
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity"
        )
        for (table,) in cursor.fetchall():
            cursor.execute(
                f"ALTER TABLE public.{connection.ops.quote_name(table)} ENABLE ROW LEVEL SECURITY"
            )


def create_profile(sender, instance, created, **kwargs):
    """Every user gets a Profile (verification state + notification prefs)."""
    if created:
        from .models import Profile

        Profile.objects.get_or_create(user=instance)


class MonitoringConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "monitoring"

    def ready(self):
        from django.conf import settings
        from django.db.models.signals import post_save

        post_migrate.connect(enable_rls_on_public_tables, sender=self)
        post_save.connect(create_profile, sender=settings.AUTH_USER_MODEL,
                          dispatch_uid="monitoring_create_profile")
