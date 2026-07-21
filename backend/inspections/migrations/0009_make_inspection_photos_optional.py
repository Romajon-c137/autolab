from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0008_vehicleinspection_country"),
    ]

    operations = [
        migrations.AlterField(
            model_name="vehicleinspection",
            name="front_photo",
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to="inspections/front/",
                verbose_name="Фото спереди",
            ),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="rear_photo",
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to="inspections/rear/",
                verbose_name="Фото сзади",
            ),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="left_photo",
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to="inspections/left/",
                verbose_name="Фото слева",
            ),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="right_photo",
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to="inspections/right/",
                verbose_name="Фото справа",
            ),
        ),
    ]
