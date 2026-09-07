from datetime import date

from django.db import migrations


def seed_o3_o4_price(apps, schema_editor):
    InspectionPrice = apps.get_model("inspections", "InspectionPrice")
    InspectionPrice.objects.update_or_create(
        operation_type="sbgts",
        vehicle_category="O3-O4",
        effective_from=date(2026, 8, 25),
        defaults={"amount": 4100, "is_active": True},
    )


def remove_o3_o4_price(apps, schema_editor):
    InspectionPrice = apps.get_model("inspections", "InspectionPrice")
    InspectionPrice.objects.filter(
        operation_type="sbgts",
        vehicle_category="O3-O4",
        effective_from=date(2026, 8, 25),
    ).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0036_add_o3_o4_category"),
    ]

    operations = [
        migrations.RunPython(seed_o3_o4_price, remove_o3_o4_price),
    ]
