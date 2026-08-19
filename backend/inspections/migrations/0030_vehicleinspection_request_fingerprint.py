from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0029_expand_media_paths"),
    ]

    operations = [
        migrations.AddField(
            model_name="vehicleinspection",
            name="request_fingerprint",
            field=models.CharField(blank=True, editable=False, max_length=64, null=True, unique=True, verbose_name="Fingerprint запроса"),
        ),
    ]
