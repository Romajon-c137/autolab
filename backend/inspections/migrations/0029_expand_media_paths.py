from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0028_expand_vehicle_identifier"),
    ]

    operations = [
        migrations.AlterField(
            model_name="vehicleinspection",
            name=name,
            field=field,
        )
        for name, field in (
            ("application_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/application/", verbose_name="Фото заявки")),
            ("front_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/front/", verbose_name="Фото спереди")),
            ("rear_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/rear/", verbose_name="Фото сзади")),
            ("left_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/left/", verbose_name="Фото слева")),
            ("right_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/right/", verbose_name="Фото справа")),
            ("mileage_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/mileage/", verbose_name="Фото пробега")),
            ("vin_photo", models.ImageField(blank=True, max_length=255, null=True, upload_to="inspections/vin/", verbose_name="Фото VIN")),
            ("document_pdf", models.FileField(blank=True, max_length=255, null=True, upload_to="inspections/documents/", verbose_name="Документ PDF")),
            ("application_pdf", models.FileField(blank=True, max_length=255, null=True, upload_to="inspections/applications/", verbose_name="PDF заявки клиента")),
        )
    ] + [
        migrations.AlterField(
            model_name="vehicleinspectionextraphoto",
            name="image",
            field=models.ImageField(max_length=255, upload_to="inspections/conversion/", verbose_name="Фото переоборудованной части"),
        ),
    ]
