from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0039_alter_file_upload_paths"),
    ]

    operations = [
        migrations.AddField(
            model_name="userprofile",
            name="ilim_smile_greeting_acknowledged_at",
            field=models.DateTimeField(
                blank=True,
                editable=False,
                null=True,
                verbose_name="Персональное приветствие Илима просмотрено",
            ),
        ),
    ]
