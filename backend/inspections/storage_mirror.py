import json
import shutil
from pathlib import Path

from django.conf import settings
from django.utils import timezone

from .models import VehicleInspection, VehicleInspectionExtraPhoto


PHOTO_FIELDS = (
    "front_photo",
    "rear_photo",
    "left_photo",
    "right_photo",
    "mileage_photo",
    "vin_photo",
    "application_photo",
)

DOCUMENT_FIELDS = (
    "document_pdf",
    "application_pdf",
)


def mirror_inspection(inspection):
    inspection_id = inspection if isinstance(inspection, int) else inspection.id
    inspection = (
        VehicleInspection.objects.select_related("branch", "created_by")
        .prefetch_related("extra_photos")
        .get(id=inspection_id)
    )

    vehicle_key = inspection.vin or f"NO_VIN_{inspection.id}"
    vehicle_dir = vehicle_storage_dir(vehicle_key)
    inspection_dir = inspection_storage_dir(inspection, vehicle_key)
    photos_dir = inspection_dir / "photos"
    documents_dir = inspection_dir / "documents"
    extra_dir = photos_dir / "extra"

    photos_dir.mkdir(parents=True, exist_ok=True)
    documents_dir.mkdir(parents=True, exist_ok=True)
    extra_dir.mkdir(parents=True, exist_ok=True)

    vehicle_data = vehicle_json(inspection)
    inspection_data = inspection_json(inspection)
    inspection_updates = {}
    extra_photo_updates = []

    for field_name in PHOTO_FIELDS:
        field = getattr(inspection, field_name, None)
        copied = copy_field_file(field, photos_dir, field_name)
        if copied:
            inspection_data["files"]["photos"][field_name] = copied
            inspection_updates[field_name] = copied

    for field_name in DOCUMENT_FIELDS:
        field = getattr(inspection, field_name, None)
        copied = copy_field_file(field, documents_dir, field_name)
        if copied:
            inspection_data["files"]["documents"][field_name] = copied
            inspection_updates[field_name] = copied

    for photo in inspection.extra_photos.all():
        copied = copy_field_file(photo.image, extra_dir, f"extra_{photo.id}")
        if copied:
            inspection_data["files"]["extra_photos"].append({
                "id": photo.id,
                "image": copied,
                "taken_at": serialize_datetime(photo.taken_at),
                "created_at": serialize_datetime(photo.created_at),
            })
            extra_photo_updates.append((photo.id, copied))

    write_json(vehicle_dir / "vehicle.json", vehicle_data)
    write_json(inspection_dir / "inspection.json", inspection_data)
    promote_inspection_files(inspection.id, inspection_updates, extra_photo_updates)
    return inspection_dir


def vehicle_storage_dir(vin):
    return storage_root() / "vehicles" / safe_path_part(vin)


def inspection_storage_dir(inspection, vehicle_key=None):
    created = timezone.localtime(inspection.created_at).strftime("%Y-%m-%d_%H%M%S")
    operation = safe_path_part(inspection.operation_type or "inspection")
    return vehicle_storage_dir(vehicle_key or inspection.vin or f"NO_VIN_{inspection.id}") / "inspections" / f"{created}_{operation}_{inspection.id}"


def storage_root():
    return Path(settings.AUTOLAB_STORAGE_ROOT)


def vehicle_json(inspection):
    return {
        "vin": inspection.vin,
        "brand": inspection.brand,
        "country": inspection.country,
        "vehicle_category": inspection.vehicle_category,
        "last_plate_number": inspection.plate_number,
        "last_operation_type": inspection.operation_type,
        "last_operation_type_label": inspection.get_operation_type_display(),
        "last_inspection_id": inspection.id,
        "last_inspection_created_at": serialize_datetime(inspection.created_at),
        "updated_at": timezone.now().isoformat(),
    }


def inspection_json(inspection):
    return {
        "id": inspection.id,
        "title": inspection.title,
        "operation_type": inspection.operation_type,
        "operation_type_label": inspection.get_operation_type_display(),
        "plate_number": inspection.plate_number,
        "brand": inspection.brand,
        "country": inspection.country,
        "vehicle_category": inspection.vehicle_category,
        "mileage": inspection.mileage,
        "amount": inspection.amount,
        "vin": inspection.vin,
        "branch": None if inspection.branch is None else {
            "id": inspection.branch.id,
            "name": inspection.branch.name,
        },
        "created_by": None if inspection.created_by is None else {
            "id": inspection.created_by.id,
            "login": inspection.created_by.get_username(),
            "first_name": inspection.created_by.first_name,
            "last_name": inspection.created_by.last_name,
        },
        "created_at": serialize_datetime(inspection.created_at),
        "photo_taken_at": {
            "front_photo": serialize_datetime(inspection.front_photo_taken_at),
            "rear_photo": serialize_datetime(inspection.rear_photo_taken_at),
            "left_photo": serialize_datetime(inspection.left_photo_taken_at),
            "right_photo": serialize_datetime(inspection.right_photo_taken_at),
            "mileage_photo": serialize_datetime(inspection.mileage_photo_taken_at),
            "vin_photo": serialize_datetime(inspection.vin_photo_taken_at),
            "application_photo": serialize_datetime(inspection.application_photo_taken_at),
        },
        "files": {
            "photos": {},
            "documents": {},
            "extra_photos": [],
        },
        "mirrored_at": timezone.now().isoformat(),
    }


def copy_field_file(field, target_dir, name_prefix):
    if not field:
        return ""

    source = Path(field.path)
    if not source.exists():
        return ""

    suffix = source.suffix.lower()
    target = target_dir / f"{safe_path_part(name_prefix)}{suffix}"
    if source.resolve() != target.resolve():
        shutil.copy2(source, target)
    return str(target.relative_to(storage_root()))


def promote_inspection_files(inspection_id, inspection_updates, extra_photo_updates):
    if inspection_updates:
        VehicleInspection.objects.filter(id=inspection_id).update(**inspection_updates)

    for photo_id, image_path in extra_photo_updates:
        VehicleInspectionExtraPhoto.objects.filter(id=photo_id).update(image=image_path)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    tmp_path.replace(path)


def safe_path_part(value):
    cleaned = "".join(char if char.isalnum() or char in ("-", "_") else "_" for char in str(value).strip())
    return cleaned or "unknown"


def serialize_datetime(value):
    return "" if value is None else timezone.localtime(value).isoformat()
