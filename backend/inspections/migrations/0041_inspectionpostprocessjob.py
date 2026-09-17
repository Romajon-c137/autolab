from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):
    dependencies = [("inspections", "0040_userprofile_ilim_smile_greeting")]

    operations = [
        migrations.CreateModel(
            name="InspectionPostprocessJob",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("base_url", models.URLField(max_length=255)),
                ("attempts", models.PositiveSmallIntegerField(default=0)),
                ("available_at", models.DateTimeField(db_index=True, default=django.utils.timezone.now)),
                ("mirror_completed_at", models.DateTimeField(blank=True, null=True)),
                ("notification_completed_at", models.DateTimeField(blank=True, null=True)),
                ("completed_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                ("delete_file_path", models.CharField(blank=True, max_length=255)),
                ("last_error", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("inspection", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name="postprocess_job", to="inspections.vehicleinspection")),
            ],
            options={"ordering": ["available_at", "id"]},
        ),
    ]
