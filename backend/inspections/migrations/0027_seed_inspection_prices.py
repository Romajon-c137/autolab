from datetime import date

from django.db import migrations


EFFECTIVE_FROM = date(2026, 8, 18)

PRICES = [
    ("sbgts", "M1", 3100),
    ("sbgts", "M2", 3350),
    ("sbgts", "M3", 3835),
    ("sbgts", "N1", 3350),
    ("sbgts", "N2", 4200),
    ("sbgts", "N3", 4600),
    ("tech_inspection", "M1", 950),
    ("tech_inspection", "M2", 950),
    ("tech_inspection", "M3", 1350),
    ("tech_inspection", "N1", 950),
    ("tech_inspection", "N2", 1200),
    ("tech_inspection", "N3", 1350),
    ("legalization", "", 1000),
    ("conversion", "", 1000),
]


def seed_prices(apps, schema_editor):
    InspectionPrice = apps.get_model("inspections", "InspectionPrice")
    VehicleInspection = apps.get_model("inspections", "VehicleInspection")

    prices = {}
    for operation_type, vehicle_category, amount in PRICES:
        InspectionPrice.objects.update_or_create(
            operation_type=operation_type,
            vehicle_category=vehicle_category,
            effective_from=EFFECTIVE_FROM,
            defaults={
                "amount": amount,
                "is_active": True,
            },
        )
        prices[(operation_type, vehicle_category)] = amount

    for inspection in VehicleInspection.objects.all().only(
        "id",
        "operation_type",
        "vehicle_category",
        "amount",
    ):
        price_category = (
            inspection.vehicle_category
            if inspection.operation_type in {"tech_inspection", "sbgts"}
            else ""
        )
        amount = prices.get((inspection.operation_type, price_category), 0)
        if inspection.amount != amount:
            inspection.amount = amount
            inspection.save(update_fields=["amount"])


def unseed_prices(apps, schema_editor):
    InspectionPrice = apps.get_model("inspections", "InspectionPrice")
    InspectionPrice.objects.filter(effective_from=EFFECTIVE_FROM).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("inspections", "0026_vehicleinspection_amount_inspectionprice"),
    ]

    operations = [
        migrations.RunPython(seed_prices, unseed_prices),
    ]
