from pathlib import Path
from urllib.parse import quote
from uuid import uuid4
import shutil
import subprocess
import tempfile

from django.conf import settings
from django.http import FileResponse, Http404


PDF_OPTIMIZE_THRESHOLD = 1024 * 1024


def optimized_pdf_url(request, field):
    if not field:
        return ""
    encoded_name = quote(field.name, safe="/")
    return request.build_absolute_uri(f"/api/pdf-preview/{encoded_name}")


def pdf_preview(request, pdf_path):
    media_root = Path(settings.MEDIA_ROOT).resolve()
    source = (media_root / pdf_path).resolve()
    allowed_roots = (
        (media_root / "inspections").resolve(),
        (media_root / "vehicles").resolve(),
    )
    if (
        not any(source.is_relative_to(root) for root in allowed_roots)
        or not source.is_file()
        or source.suffix.lower() != ".pdf"
    ):
        raise Http404("PDF not found")

    if source.stat().st_size <= PDF_OPTIMIZE_THRESHOLD or shutil.which("gs") is None:
        return _pdf_response(source)

    cache_path = _ensure_optimized_pdf(source, media_root, pdf_path)
    return _pdf_response(cache_path)


def warm_pdf_preview(pdf_path):
    if not pdf_path or shutil.which("gs") is None:
        return
    media_root = Path(settings.MEDIA_ROOT).resolve()
    source = (media_root / pdf_path).resolve()
    if source.is_file() and source.suffix.lower() == ".pdf" and source.stat().st_size > PDF_OPTIMIZE_THRESHOLD:
        try:
            _ensure_optimized_pdf(source, media_root, pdf_path)
        except (Http404, OSError):
            return


def _ensure_optimized_pdf(source, media_root, pdf_path):
    cache_path = media_root / ".previews" / f"{pdf_path}.optimized.pdf"
    if not cache_path.exists() or cache_path.stat().st_mtime < source.stat().st_mtime:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        temporary_cache = cache_path.with_name(f".{cache_path.name}.{uuid4().hex}.tmp")
        try:
            with tempfile.TemporaryDirectory(prefix="autolab-pdf-") as directory:
                temporary_source = Path(directory) / "source.pdf"
                temporary_output = Path(directory) / "optimized.pdf"
                shutil.copyfile(source, temporary_source)
                try:
                    subprocess.run(
                        [
                            "gs",
                            "-dNOSAFER",
                            "-sDEVICE=pdfwrite",
                            "-dCompatibilityLevel=1.6",
                            "-dPDFSETTINGS=/ebook",
                            "-dColorImageResolution=120",
                            "-dGrayImageResolution=120",
                            "-dMonoImageResolution=300",
                            "-dDetectDuplicateImages=true",
                            "-dNOPAUSE",
                            "-dQUIET",
                            "-dBATCH",
                            f"-sOutputFile={temporary_output}",
                            str(temporary_source),
                        ],
                        check=True,
                        timeout=60,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                except (subprocess.SubprocessError, OSError) as error:
                    raise Http404("PDF cannot be optimized") from error

                selected = (
                    temporary_output
                    if temporary_output.is_file()
                    and temporary_output.stat().st_size < source.stat().st_size
                    else temporary_source
                )
                shutil.copyfile(selected, temporary_cache)
            temporary_cache.replace(cache_path)
        finally:
            temporary_cache.unlink(missing_ok=True)

    return cache_path


def _pdf_response(path):
    response = FileResponse(path.open("rb"), content_type="application/pdf")
    response["Cache-Control"] = "public, max-age=604800"
    response["X-Content-Type-Options"] = "nosniff"
    return response
