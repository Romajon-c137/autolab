from django.core.files import File
from django.utils import timezone

from .models import VehicleInspection


def save_client_application_pdf(inspection, uploaded_pdf, vin):
    filename = f"application_{vin}_{timezone.now().strftime('%Y%m%d%H%M%S')}.pdf"
    inspection.application_pdf.save(filename, uploaded_pdf, save=True)
    return inspection.application_pdf


def attach_existing_application_pdf(inspection):
    if inspection.operation_type == VehicleInspection.OPERATION_SBGTS:
        return False

    if inspection.application_pdf:
        return False

    source = (
        VehicleInspection.objects
        .filter(vin__iexact=inspection.vin)
        .exclude(id=inspection.id)
        .exclude(application_pdf="")
        .filter(application_pdf__isnull=False)
        .order_by("-created_at", "-id")
        .first()
    )
    if source is None or not source.application_pdf:
        return False

    try:
        source_path = source.application_pdf.path
    except (NotImplementedError, ValueError):
        return False

    filename = f"application_{inspection.vin}_{timezone.now().strftime('%Y%m%d%H%M%S')}.pdf"
    with open(source_path, "rb") as source_file:
        inspection.application_pdf.save(filename, File(source_file), save=True)
    return True
