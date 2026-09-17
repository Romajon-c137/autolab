from django.core.files import File
from django.db import transaction
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
    signature,
    request_id=None,
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
        request_id=request_id,
    )
    application.pdf.save(filename, uploaded_pdf, save=False)
    application.signature.save(f"signature_{vin}_{timezone.now().strftime('%Y%m%d%H%M%S')}.png", signature, save=False)
    try:
        application.save()
    except Exception:
        if application.pdf:
            application.pdf.storage.delete(application.pdf.name)
        if application.signature:
            application.signature.storage.delete(application.signature.name)
        raise
    return application


def detach_application(application):
    """Detach an application and remove its copy from the previously linked inspection."""
    inspection = application.inspection
    if inspection is not None and inspection.application_pdf:
        old_pdf_name = inspection.application_pdf.name
        inspection.application_pdf = None
        inspection.save(update_fields=["application_pdf"])

        def clean_old_inspection():
            from .background_tasks import schedule_inspection_archive
            schedule_inspection_archive(inspection.id, delete_file_path=old_pdf_name)

        transaction.on_commit(clean_old_inspection)
    application.inspection = None
    application.save(update_fields=["inspection"])


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
