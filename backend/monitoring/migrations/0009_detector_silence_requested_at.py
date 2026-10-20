from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('monitoring', '0008_detector_members'),
    ]

    operations = [
        migrations.AddField(
            model_name='detector',
            name='silence_requested_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
