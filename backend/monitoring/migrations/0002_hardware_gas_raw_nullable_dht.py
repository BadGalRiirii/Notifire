from django.db import migrations, models


class Migration(migrations.Migration):
    """Switch to real ESP32 hardware: MQ-5 reports raw ADC (not ppm), DHT22
    readings may be missing on sensor error, and simulator rows are purged."""

    dependencies = [
        ("monitoring", "0001_initial"),
    ]

    operations = [
        migrations.RunSQL(
            "DELETE FROM monitoring_detectionlog WHERE reading_id IN "
            "(SELECT id FROM monitoring_sensorreading WHERE source = 'simulator'); "
            "DELETE FROM monitoring_sensorreading WHERE source = 'simulator';",
            reverse_sql=migrations.RunSQL.noop,
        ),
        migrations.RenameField("sensorreading", "ppm", "gas"),
        migrations.RenameField("detectionlog", "ppm", "gas"),
        migrations.AlterField(
            model_name="sensorreading",
            name="temperature",
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="sensorreading",
            name="humidity",
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="sensorreading",
            name="source",
            field=models.CharField(default="esp32", max_length=32),
        ),
        migrations.AlterField(
            model_name="detectionlog",
            name="temperature",
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="detectionlog",
            name="humidity",
            field=models.FloatField(blank=True, null=True),
        ),
    ]
