import inspections.models
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0038_merge_milestone_and_o3_o4"),
    ]

    operations = [
        migrations.AlterField(
            model_name="clientapplication",
            name="pdf",
            field=models.FileField(max_length=255, upload_to=inspections.models.client_application_upload_to, verbose_name="PDF заявки"),
        ),
        migrations.AlterField(
            model_name="clientapplication",
            name="signature",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.client_application_upload_to, verbose_name="Подпись заявителя"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="application_pdf",
            field=models.FileField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="PDF заявки клиента"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="application_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото заявки"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="document_pdf",
            field=models.FileField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Документ PDF"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="front_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото спереди"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="left_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото слева"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="mileage_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото пробега"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="rear_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото сзади"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="right_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото справа"),
        ),
        migrations.AlterField(
            model_name="vehicleinspection",
            name="vin_photo",
            field=models.ImageField(blank=True, max_length=255, null=True, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото VIN"),
        ),
        migrations.AlterField(
            model_name="vehicleinspectionextraphoto",
            name="image",
            field=models.ImageField(max_length=255, upload_to=inspections.models.vehicle_staging_upload_to, verbose_name="Фото переоборудованной части"),
        ),
    ]
