from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("inspections", "0033_clientapplication_plate_number_and_more")]

    operations = [
        migrations.AddField(
            model_name="clientapplication",
            name="signature",
            field=models.ImageField(
                blank=True,
                max_length=255,
                null=True,
                upload_to="inspections/application_signatures/",
                verbose_name="Подпись заявителя",
            ),
        ),
    ]
