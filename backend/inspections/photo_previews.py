from pathlib import Path
from urllib.parse import quote
from uuid import uuid4

from django.conf import settings
from django.http import FileResponse, Http404
from PIL import Image, ImageOps


PREVIEW_MAX_SIZE = (1920, 1920)
PREVIEW_WEBP_QUALITY = 82
SUPPORTED_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}


def preview_file_url(request, field):
    if not field:
        return ""
    encoded_name = quote(field.name, safe="/")
    return request.build_absolute_uri(f"/api/photo-preview/{encoded_name}")


def photo_preview(request, photo_path):
    media_root = Path(settings.MEDIA_ROOT).resolve()
    source = (media_root / photo_path).resolve()
    inspections_root = (media_root / "inspections").resolve()
    if (
        not source.is_relative_to(inspections_root)
        or not source.is_file()
        or source.suffix.lower() not in SUPPORTED_IMAGE_SUFFIXES
    ):
        raise Http404("Photo not found")

    cache_path = media_root / ".previews" / f"{photo_path}.webp"
    if not cache_path.exists() or cache_path.stat().st_mtime < source.stat().st_mtime:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = cache_path.with_name(f".{cache_path.name}.{uuid4().hex}.tmp")
        try:
            try:
                with Image.open(source) as original:
                    image = ImageOps.exif_transpose(original)
                    image.thumbnail(PREVIEW_MAX_SIZE, Image.Resampling.LANCZOS)
                    if image.mode != "RGB":
                        image = image.convert("RGB")
                    image.save(
                        temporary_path,
                        format="WEBP",
                        quality=PREVIEW_WEBP_QUALITY,
                        method=4,
                    )
            except (OSError, ValueError) as error:
                raise Http404("Photo cannot be previewed") from error
            temporary_path.replace(cache_path)
        finally:
            temporary_path.unlink(missing_ok=True)

    response = FileResponse(cache_path.open("rb"), content_type="image/webp")
    response["Cache-Control"] = "public, max-age=604800"
    response["X-Content-Type-Options"] = "nosniff"
    return response
