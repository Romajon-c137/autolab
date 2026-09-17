from django.utils import timezone

from .models import InspectionPrice, VehicleInspection


class MissingInspectionPrice(ValueError):
    pass


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
    if price is None:
        category = f" / {price_category}" if price_category else ""
        raise MissingInspectionPrice(f"Не настроен действующий тариф: {operation_type}{category}")
    return price.amount
