from django.core.files import File
from django.utils import timezone

from .models import ClientApplication, VehicleInspection


def save_client_application(
    vin,
    applicant_name,
    inn,
    phone,
    vehicle_name,
    plate_number,
    year,
    uploaded_pdf,
):
    filename = f"application_{vin}_{timezone.now().strftime('%Y%m%d%H%M%S')}.pdf"
    application = ClientApplication(
        applicant_name=applicant_name,
        inn=inn,
        phone=phone,
        vehicle_name=vehicle_name,
        plate_number=plate_number,
        year=year,
        vin=vin,
    )
    application.pdf.save(filename, uploaded_pdf, save=False)
    application.save()
    return application


def _copy_pdf_to_inspection(inspection, application):
    if not application.pdf:
        return

    filename = f"application_{application.vin}_{timezone.now().strftime('%Y%m%d%H%M%S')}.pdf"
    application.pdf.open("rb")
    try:
        inspection.application_pdf.save(filename, File(application.pdf), save=True)
    finally:
        application.pdf.close()


def link_application_on_submit(application):
    """A ClientApplication was just created: try to find a matching inspection by VIN."""
    inspection = (
        VehicleInspection.objects
        .filter(vin__iexact=application.vin)
        .order_by("-created_at")
        .first()
    )
    if inspection is None:
        return None

    application.inspection = inspection
    application.save(update_fields=["inspection"])
    if not inspection.application_pdf:
        _copy_pdf_to_inspection(inspection, application)
    return inspection


def link_application_on_inspection_created(inspection):
    """An Inspection was just created: try to find a matching unlinked ClientApplication."""
    application = (
        ClientApplication.objects
        .filter(vin__iexact=inspection.vin, inspection__isnull=True)
        .order_by("-created_at")
        .first()
    )
    if application is None:
        return False

    application.inspection = inspection
    application.save(update_fields=["inspection"])
    if not inspection.application_pdf:
        _copy_pdf_to_inspection(inspection, application)
    return True
