from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("inspections", "0030_vehicleinspection_request_fingerprint"),
    ]

    operations = [
        migrations.CreateModel(
            name="ApiRateLimit",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("scope", models.CharField(max_length=64)),
                ("identity_hash", models.CharField(max_length=64)),
                ("bucket", models.BigIntegerField()),
                ("count", models.PositiveIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.AddConstraint(
            model_name="apiratelimit",
            constraint=models.UniqueConstraint(fields=("scope", "identity_hash", "bucket"), name="unique_api_rate_limit_bucket"),
        ),
    ]
