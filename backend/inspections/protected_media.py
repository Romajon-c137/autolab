import mimetypes
from pathlib import Path
from urllib.parse import unquote, urlsplit

from django.conf import settings
from django.db.models import Q
from django.http import FileResponse, Http404, HttpResponse

from .access import allowed_inspections, can_manage_applications, require_auth
from .models import ClientApplication, VehicleInspectionExtraPhoto


INSPECTION_FILE_FIELDS = (
    "front_photo",
    "rear_photo",
    "left_photo",
    "right_photo",
    "mileage_photo",
    "vin_photo",
    "application_photo",
    "document_pdf",
    "application_pdf",
)
IMAGE_FILE_FIELDS = INSPECTION_FILE_FIELDS[:7]


def _inspection_file_query(path, fields):
    query = Q()
    for field_name in fields:
        query |= Q(**{field_name: path})
    return query


def authorize_media_path(request, media_path, *, images_only=False):
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error

    normalized = Path(media_path).as_posix().lstrip("/")
    fields = IMAGE_FILE_FIELDS if images_only else INSPECTION_FILE_FIELDS
    if allowed_inspections(user, include_files=False).filter(
        _inspection_file_query(normalized, fields)
    ).exists():
        return None

    if VehicleInspectionExtraPhoto.objects.filter(
        inspection__in=allowed_inspections(user, include_files=False),
        image=normalized,
    ).exists():
        return None

    if not images_only and can_manage_applications(user):
        application_query = Q(pdf=normalized)
        if user.is_staff:
            application_query |= Q(signature=normalized)
        if ClientApplication.objects.filter(application_query).exists():
            return None

    raise Http404("File not found")


def protected_media(request, media_path):
    authorization_error = authorize_media_path(request, media_path)
    if authorization_error is not None:
        return authorization_error

    media_root = Path(settings.MEDIA_ROOT).resolve()
    source = (media_root / media_path).resolve()
    if not source.is_relative_to(media_root) or not source.is_file():
        raise Http404("File not found")

    content_type = mimetypes.guess_type(source.name)[0] or "application/octet-stream"
    response = FileResponse(source.open("rb"), content_type=content_type)
    response["Cache-Control"] = "private, max-age=3600"
    response["X-Content-Type-Options"] = "nosniff"
    return response


def media_authorize(request):
    original_uri = request.headers.get("X-Original-URI", "")
    path = unquote(urlsplit(original_uri).path)
    if not path.startswith("/media/"):
        raise Http404("File not found")
    authorization_error = authorize_media_path(request, path.removeprefix("/media/"))
    if authorization_error is not None:
        return authorization_error
    return HttpResponse(status=204)
