from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0009_make_inspection_photos_optional"),
    ]

    operations = [
        migrations.AddField(
            model_name="vehicleinspection",
            name="document_pdf",
            field=models.FileField(
                blank=True,
                null=True,
                upload_to="inspections/documents/",
                verbose_name="Документ PDF",
            ),
        ),
    ]
