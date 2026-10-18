from django.db import migrations, models


class Migration(migrations.Migration):
    """Remember the last pushed alert so a "back to normal" push can replace it."""

    dependencies = [
        ("monitoring", "0006_accounts_push_offline"),
    ]

    operations = [
        migrations.AddField(
            model_name="detector",
            name="alert_level",
            field=models.CharField(blank=True, max_length=10),
        ),
    ]
