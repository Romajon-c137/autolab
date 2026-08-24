from .photo_previews import preview_file_url


def file_url(request, field):
    if not field:
        return ""

    return request.build_absolute_uri(field.url)


def serialize_application(request, application):
    return {
        "id": application.id,
        "applicant_name": application.applicant_name,
        "inn": application.inn,
        "phone": application.phone,
        "vehicle_name": application.vehicle_name,
        "plate_number": application.plate_number,
        "year": application.year,
        "vin": application.vin,
        "pdf": file_url(request, application.pdf),
        "created_at": application.created_at.isoformat(),
        "inspection_id": application.inspection_id,
        "can_rebuild": bool(application.signature),
    }


def serialize_datetime(value):
    return "" if value is None else value.isoformat()


def serialize_inspection(
    request,
    inspection,
    *,
    include_amount=True,
    include_application=True,
    include_files=True,
):
    data = {
        "id": inspection.id,
        "operation_type": inspection.operation_type,
        "operation_type_label": inspection.get_operation_type_display(),
        "brand": inspection.brand,
        "vehicle_category": inspection.vehicle_category,
        "vin": inspection.vin,
        "created_at": inspection.created_at.isoformat(),
        "branch": None if inspection.branch is None else {
            "id": inspection.branch.id,
            "name": inspection.branch.name,
        },
        "created_by": None if inspection.created_by is None else {
            "id": inspection.created_by.id,
            "login": inspection.created_by.get_username(),
            "first_name": inspection.created_by.first_name,
            "last_name": inspection.created_by.last_name,
            "full_name": inspection.created_by.get_full_name()
            or inspection.created_by.get_username(),
        },
    }
    if include_files:
        data["title"] = inspection.title
        data["plate_number"] = inspection.plate_number
        data["country"] = inspection.country
        data["photo_taken_at"] = {
            "front_photo": serialize_datetime(inspection.front_photo_taken_at),
            "rear_photo": serialize_datetime(inspection.rear_photo_taken_at),
            "left_photo": serialize_datetime(inspection.left_photo_taken_at),
            "right_photo": serialize_datetime(inspection.right_photo_taken_at),
            "mileage_photo": serialize_datetime(inspection.mileage_photo_taken_at),
            "vin_photo": serialize_datetime(inspection.vin_photo_taken_at),
        }
        data["photos"] = {
            "front_photo": preview_file_url(request, inspection.front_photo),
            "rear_photo": preview_file_url(request, inspection.rear_photo),
            "left_photo": preview_file_url(request, inspection.left_photo),
            "right_photo": preview_file_url(request, inspection.right_photo),
            "mileage_photo": preview_file_url(request, inspection.mileage_photo),
            "vin_photo": preview_file_url(request, inspection.vin_photo),
        }
        data["extra_photos"] = [
            {
                "id": photo.id,
                "image": preview_file_url(request, photo.image),
                "taken_at": serialize_datetime(photo.taken_at),
            }
            for photo in inspection.extra_photos.all()
        ]
        data["document_pdf"] = file_url(request, inspection.document_pdf)
    if include_amount:
        data["amount"] = inspection.amount
    if include_application and include_files:
        data["application_pdf"] = file_url(request, inspection.application_pdf)
    return data
