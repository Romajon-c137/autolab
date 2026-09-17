import logging
from datetime import timedelta

from django.db import transaction
from django.core.files.storage import default_storage
from django.utils import timezone

from .models import InspectionPostprocessJob, VehicleInspection
from .notifications import notify_telegram_inspection_created
from .storage_mirror import mirror_inspection


logger = logging.getLogger(__name__)


def schedule_inspection_postprocessing(inspection_id, base_url):
    InspectionPostprocessJob.objects.update_or_create(
        inspection_id=inspection_id,
        defaults={
            "base_url": base_url,
            "available_at": timezone.now(),
            "notification_completed_at": None,
            "completed_at": None,
        },
    )


def schedule_inspection_archive(inspection_id, delete_file_path=""):
    job, _created = InspectionPostprocessJob.objects.get_or_create(
        inspection_id=inspection_id,
        defaults={
            "base_url": "https://autolab.glasscenter.kg",
            "notification_completed_at": timezone.now(),
        },
    )
    job.mirror_completed_at = None
    job.completed_at = None
    job.available_at = timezone.now()
    if delete_file_path:
        job.delete_file_path = delete_file_path
    job.save(update_fields=[
        "mirror_completed_at", "completed_at", "available_at",
        "delete_file_path", "updated_at",
    ])


def process_next_postprocessing_job():
    now = timezone.now()
    with transaction.atomic():
        job = (
            InspectionPostprocessJob.objects.select_for_update(skip_locked=True)
            .filter(completed_at__isnull=True, available_at__lte=now)
            .order_by("available_at", "id")
            .first()
        )
        if job is None:
            return False
        job.attempts += 1
        job.available_at = now + timedelta(minutes=min(30, 2 ** min(job.attempts, 5)))
        job.save(update_fields=["attempts", "available_at", "updated_at"])

    try:
        if job.delete_file_path:
            default_storage.delete(job.delete_file_path)
            job.delete_file_path = ""
            job.save(update_fields=["delete_file_path", "updated_at"])

        if job.mirror_completed_at is None:
            mirror_inspection(job.inspection_id)
            job.mirror_completed_at = timezone.now()
            job.save(update_fields=["mirror_completed_at", "updated_at"])

        if job.notification_completed_at is None:
            inspection = VehicleInspection.objects.select_related(
                "branch", "created_by"
            ).get(id=job.inspection_id)
            notify_telegram_inspection_created(job.base_url, inspection)
            job.notification_completed_at = timezone.now()

        job.completed_at = timezone.now()
        job.last_error = ""
        job.save(update_fields=[
            "notification_completed_at", "completed_at", "last_error", "updated_at"
        ])
    except Exception as error:
        job.last_error = str(error)[:4000]
        job.save(update_fields=["last_error", "updated_at"])
        logger.exception("Postprocessing failed for inspection %s", job.inspection_id)
    return True
