import hashlib
from datetime import timedelta
from io import BytesIO

from PIL import Image, UnidentifiedImageError
from pillow_heif import register_heif_opener
from django.conf import settings
from django.db.models import F
from django.utils import timezone


class UploadValidationError(ValueError):
    pass


register_heif_opener()


def client_ip(request):
    remote = request.META.get("REMOTE_ADDR", "")
    if remote in {"127.0.0.1", "::1"}:
        forwarded = request.headers.get("X-Forwarded-For", "")
        if forwarded:
            return forwarded.split(",", 1)[0].strip()
    return remote or "unknown"


def rate_limit(request, scope, limit, period_seconds):
    from .models import ApiRateLimit

    bucket = int(__import__("time").time()) // period_seconds
    identity = hashlib.sha256(client_ip(request).encode()).hexdigest()
    record, created = ApiRateLimit.objects.get_or_create(
        scope=scope,
        identity_hash=identity,
        bucket=bucket,
        defaults={"count": 1},
    )
    if created:
        if bucket % 60 == 0:
            ApiRateLimit.objects.filter(created_at__lt=timezone.now() - timedelta(days=2)).delete()
        return True
    ApiRateLimit.objects.filter(pk=record.pk).update(count=F("count") + 1)
    record.refresh_from_db(fields=["count"])
    return record.count <= limit


def validate_image(uploaded_file):
    if uploaded_file.size > settings.MAX_IMAGE_UPLOAD_BYTES:
        raise UploadValidationError("Image is too large")
    if uploaded_file.size <= 0:
        raise UploadValidationError("Image is empty")

    position = uploaded_file.tell()
    try:
        data = uploaded_file.read(settings.MAX_IMAGE_UPLOAD_BYTES + 1)
        image = Image.open(BytesIO(data))
        image.verify()
        if image.format not in {"JPEG", "PNG", "GIF", "WEBP", "HEIF"}:
            raise UploadValidationError("Unsupported image format")
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise UploadValidationError("Uploaded file is not a valid image") from exc
    finally:
        uploaded_file.seek(position)


def validate_pdf(uploaded_file):
    if uploaded_file.size > settings.MAX_PDF_UPLOAD_BYTES:
        raise UploadValidationError("PDF is too large")
    if uploaded_file.size < 5:
        raise UploadValidationError("PDF is empty")
    position = uploaded_file.tell()
    try:
        if uploaded_file.read(5) != b"%PDF-":
            raise UploadValidationError("Uploaded file is not a valid PDF")
    finally:
        uploaded_file.seek(position)


def inspection_fingerprint(user_id, fields, uploaded_files):
    digest = hashlib.sha256()
    digest.update(str(user_id).encode())
    for value in fields:
        digest.update(b"\0")
        digest.update(str(value).strip().encode("utf-8"))
    for uploaded_file in uploaded_files:
        digest.update(b"\0file\0")
        if uploaded_file is None:
            continue
        position = uploaded_file.tell()
        try:
            for chunk in uploaded_file.chunks():
                digest.update(chunk)
        finally:
            uploaded_file.seek(position)
    return digest.hexdigest()
