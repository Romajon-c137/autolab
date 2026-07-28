from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0013_dailyinspectionreport"),
    ]

    operations = [
        migrations.DeleteModel(
            name="AiApiKey",
        ),
    ]
