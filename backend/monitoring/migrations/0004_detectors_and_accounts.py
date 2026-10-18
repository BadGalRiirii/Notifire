import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models

import monitoring.models


class Migration(migrations.Migration):
    """Multi-detector accounts: each user owns detectors identified by a unique
    code. Replaces the single global DeviceState. Readings/logs recorded before
    detectors existed can't be attributed to one, so they are removed."""

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("monitoring", "0003_supabase_enable_rls"),
    ]

    operations = [
        migrations.RunSQL(
            "DELETE FROM monitoring_detectionlog; DELETE FROM monitoring_sensorreading;",
            reverse_sql=migrations.RunSQL.noop,
        ),
        migrations.CreateModel(
            name="Detector",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("name", models.CharField(max_length=60)),
                ("location", models.CharField(blank=True, max_length=120)),
                ("code", models.CharField(default=monitoring.models.generate_detector_code, editable=False, max_length=16, unique=True)),
                ("mq5_enabled", models.BooleanField(default=True)),
                ("last_seen_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("owner", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="detectors", to=settings.AUTH_USER_MODEL)),
            ],
            options={"ordering": ["created_at"]},
        ),
        migrations.DeleteModel(name="DeviceState"),
        migrations.RemoveField(model_name="sensorreading", name="source"),
        migrations.AddField(
            model_name="sensorreading",
            name="detector",
            field=models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="readings", to="monitoring.detector"),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name="detectionlog",
            name="detector",
            field=models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="logs", to="monitoring.detector"),
            preserve_default=False,
        ),
    ]
