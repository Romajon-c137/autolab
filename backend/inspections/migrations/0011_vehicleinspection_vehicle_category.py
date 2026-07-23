from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0010_vehicleinspection_document_pdf"),
    ]

    operations = [
        migrations.AddField(
            model_name="vehicleinspection",
            name="vehicle_category",
            field=models.CharField(
                choices=[("M1", "M1"), ("N1", "N1")],
                default="M1",
                max_length=2,
                verbose_name="Категория авто",
            ),
        ),
    ]
