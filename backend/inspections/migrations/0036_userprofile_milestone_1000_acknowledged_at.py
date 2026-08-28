from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0035_alter_userprofile_role"),
    ]

    operations = [
        migrations.AddField(
            model_name="userprofile",
            name="milestone_1000_acknowledged_at",
            field=models.DateTimeField(
                blank=True,
                editable=False,
                null=True,
                verbose_name="Поздравление 1000 осмотров просмотрено",
            ),
        ),
    ]
