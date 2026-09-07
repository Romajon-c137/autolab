from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0035_alter_userprofile_role"),
    ]

    operations = [
        migrations.AlterField(
            model_name="vehicleinspection",
            name="vehicle_category",
            field=models.CharField(
                choices=[
                    ("M1", "M1"),
                    ("M2", "M2"),
                    ("M3", "M3"),
                    ("N1", "N1"),
                    ("N2", "N2"),
                    ("N3", "N3"),
                    ("O3-O4", "O3-O4"),
                ],
                default="M1",
                max_length=5,
                verbose_name="Категория авто",
            ),
        ),
        migrations.AlterField(
            model_name="inspectionprice",
            name="vehicle_category",
            field=models.CharField(
                blank=True,
                choices=[
                    ("M1", "M1"),
                    ("M2", "M2"),
                    ("M3", "M3"),
                    ("N1", "N1"),
                    ("N2", "N2"),
                    ("N3", "N3"),
                    ("O3-O4", "O3-O4"),
                ],
                help_text="Заполняется для СБКТС и техосмотра. Для остальных операций оставить пустым.",
                max_length=5,
                verbose_name="Категория авто",
            ),
        ),
    ]
