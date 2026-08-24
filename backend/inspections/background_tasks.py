import logging
import threading

from django.db import close_old_connections

from .models import VehicleInspection
from .notifications import notify_telegram_inspection_created
from .storage_mirror import mirror_inspection


logger = logging.getLogger(__name__)


def schedule_inspection_postprocessing(inspection_id, base_url):
    thread = threading.Thread(
        target=_postprocess_inspection,
        args=(inspection_id, base_url),
        name=f"inspection-postprocess-{inspection_id}",
        daemon=True,
    )
    thread.start()


def _postprocess_inspection(inspection_id, base_url):
    close_old_connections()
    try:
        try:
            mirror_inspection(inspection_id)
        except Exception:
            logger.exception("Storage mirroring failed for inspection %s", inspection_id)

        try:
            inspection = VehicleInspection.objects.select_related(
                "branch",
                "created_by",
            ).get(id=inspection_id)
            notify_telegram_inspection_created(base_url, inspection)
        except Exception:
            logger.exception("Notification failed for inspection %s", inspection_id)
    finally:
        close_old_connections()
