from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0027_seed_inspection_prices"),
    ]

    operations = [
        migrations.AlterField(
            model_name="vehicleinspection",
            name="vin",
            field=models.CharField(max_length=32, verbose_name="VIN / номер кузова"),
        ),
    ]
