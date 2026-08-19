def file_url(request, field):
    if not field:
        return ""

    return request.build_absolute_uri(field.url)


def serialize_datetime(value):
    return "" if value is None else value.isoformat()


def serialize_inspection(request, inspection):
    return {
        "id": inspection.id,
        "title": inspection.title,
        "operation_type": inspection.operation_type,
        "operation_type_label": inspection.get_operation_type_display(),
        "plate_number": inspection.plate_number,
        "brand": inspection.brand,
        "country": inspection.country,
        "vehicle_category": inspection.vehicle_category,
        "amount": inspection.amount,
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
        "photos": {
            "front_photo": file_url(request, inspection.front_photo),
            "rear_photo": file_url(request, inspection.rear_photo),
            "left_photo": file_url(request, inspection.left_photo),
            "right_photo": file_url(request, inspection.right_photo),
            "mileage_photo": file_url(request, inspection.mileage_photo),
            "vin_photo": file_url(request, inspection.vin_photo),
        },
        "extra_photos": [
            {
                "id": photo.id,
                "image": file_url(request, photo.image),
                "taken_at": serialize_datetime(photo.taken_at),
            }
            for photo in inspection.extra_photos.all()
        ],
        "document_pdf": file_url(request, inspection.document_pdf),
        "application_pdf": file_url(request, inspection.application_pdf),
        "photo_taken_at": {
            "front_photo": serialize_datetime(inspection.front_photo_taken_at),
            "rear_photo": serialize_datetime(inspection.rear_photo_taken_at),
            "left_photo": serialize_datetime(inspection.left_photo_taken_at),
            "right_photo": serialize_datetime(inspection.right_photo_taken_at),
            "mileage_photo": serialize_datetime(inspection.mileage_photo_taken_at),
            "vin_photo": serialize_datetime(inspection.vin_photo_taken_at),
        },
    }
