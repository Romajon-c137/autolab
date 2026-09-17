from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("inspections", "0041_inspectionpostprocessjob")]

    operations = [
        migrations.AddField(
            model_name="clientapplication",
            name="request_id",
            field=models.CharField(blank=True, editable=False, max_length=64, null=True, unique=True),
        ),
    ]
