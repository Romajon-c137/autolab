from django.utils import timezone

from .models import InspectionPrice, VehicleInspection


def current_inspection_amount(operation_type, vehicle_category):
    """Return the active price for an inspection operation and category."""
    price_category = (
        vehicle_category
        if operation_type in {
            VehicleInspection.OPERATION_TECH_INSPECTION,
            VehicleInspection.OPERATION_SBGTS,
        }
        else ""
    )
    price = (
        InspectionPrice.objects.filter(
            operation_type=operation_type,
            vehicle_category=price_category,
            is_active=True,
            effective_from__lte=timezone.localdate(),
        )
        .order_by("-effective_from", "-id")
        .first()
    )
    return 0 if price is None else price.amount
