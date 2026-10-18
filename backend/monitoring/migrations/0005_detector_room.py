from django.db import migrations, models


def fill_room(apps, schema_editor):
    """Before this change the room was typed into `name` (e.g. "Bedroom") and
    `location` held extra detail (e.g. "2nd floor"); move the name into room."""
    Detector = apps.get_model("monitoring", "Detector")
    for d in Detector.objects.all():
        d.room = d.name
        d.name = f"{d.name} Detector"
        d.save(update_fields=["room", "name"])


class Migration(migrations.Migration):
    """Detectors get a required room name plus an optional detector name,
    replacing the free-text location field."""

    dependencies = [
        ("monitoring", "0004_detectors_and_accounts"),
    ]

    operations = [
        migrations.RenameField("detector", "location", "room"),
        migrations.AlterField(
            model_name="detector",
            name="room",
            field=models.CharField(max_length=60),
        ),
        migrations.RunPython(fill_room, migrations.RunPython.noop),
    ]
