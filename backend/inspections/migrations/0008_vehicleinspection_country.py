from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0007_vehicleinspection_front_photo_taken_at_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="vehicleinspection",
            name="country",
            field=models.CharField(blank=True, max_length=80, verbose_name="Страна"),
        ),
    ]
