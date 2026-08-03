from datetime import datetime, timedelta
import base64
from io import BytesIO
import html
import json
import os
import re

from django.contrib.auth import authenticate, login, logout
from django.contrib.auth import get_user_model
from django.contrib.sessions.models import Session
from django.db.models import Count
from django.http import JsonResponse
from django.utils.dateparse import parse_datetime
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from PIL import Image, ImageEnhance, ImageFilter, ImageOps
import requests

from .models import (
    Branch,
    DailyInspectionReport,
    OpenAIApiKey,
    UserProfile,
    VehicleInspection,
    VehicleInspectionExtraPhoto,
)

REQUIRED_PHOTO_FIELDS = (
    "application_photo",
    "front_photo",
    "rear_photo",
    "left_photo",
    "right_photo",
    "mileage_photo",
    "vin_photo",
)
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}
VIN_PATTERN = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
VIN_CANDIDATE_PATTERN = re.compile(r"[A-HJ-NPR-Z0-9]{17}")


def _json_body(request):
    if not request.body:
        return {}

    try:
        return json.loads(request.body.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def _require_auth(request):
    if request.user.is_authenticated:
        return None, request.user

    session_key = request.headers.get("X-Session-Key", "").strip()
    if session_key:
        session = Session.objects.filter(session_key=session_key).first()
        if session is not None:
            user_id = session.get_decoded().get("_auth_user_id")
            user = get_user_model().objects.filter(id=user_id, is_active=True).first()
            if user is not None:
                return None, user

    return JsonResponse({
        "ok": False,
        "error": "Authentication required",
    }, status=401), None


def _profile_for(user):
    profile, _created = UserProfile.objects.get_or_create(user=user)
    return profile


def _is_report_user(user):
    profile = _profile_for(user)
    return user.is_superuser or profile.role in (
        UserProfile.ROLE_MANAGER,
        UserProfile.ROLE_ADMIN,
    )


def _allowed_inspections(user):
    profile = _profile_for(user)
    queryset = VehicleInspection.objects.select_related(
        "branch",
        "created_by",
    ).prefetch_related("extra_photos")

    if user.is_superuser or profile.role == UserProfile.ROLE_ADMIN:
        return queryset

    if profile.branch_id is None:
        return queryset.none()

    return queryset.filter(branch_id=profile.branch_id)


def _date_range(request):
    date_from_raw = request.GET.get("date_from", "")
    date_to_raw = request.GET.get("date_to", "")
    today = timezone.localdate()

    try:
        date_from = (
            datetime.strptime(date_from_raw, "%Y-%m-%d").date()
            if date_from_raw
            else today.replace(day=1)
        )
        date_to = (
            datetime.strptime(date_to_raw, "%Y-%m-%d").date()
            if date_to_raw
            else today
        )
    except ValueError:
        return None, None, JsonResponse({
            "ok": False,
            "error": "Dates must be YYYY-MM-DD",
        }, status=400)

    start = timezone.make_aware(datetime.combine(date_from, datetime.min.time()))
    end = timezone.make_aware(datetime.combine(date_to + timedelta(days=1), datetime.min.time()))
    return start, end, None


def _file_url(request, field):
    if not field:
        return ""

    return request.build_absolute_uri(field.url)


def _serialize_datetime(value):
    return "" if value is None else value.isoformat()


def _serialize_inspection(request, inspection):
    return {
        "id": inspection.id,
        "title": inspection.title,
        "operation_type": inspection.operation_type,
        "operation_type_label": inspection.get_operation_type_display(),
        "plate_number": inspection.plate_number,
        "brand": inspection.brand,
        "country": inspection.country,
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
        },
        "photos": {
            "application_photo": _file_url(request, inspection.application_photo),
            "front_photo": _file_url(request, inspection.front_photo),
            "rear_photo": _file_url(request, inspection.rear_photo),
            "left_photo": _file_url(request, inspection.left_photo),
            "right_photo": _file_url(request, inspection.right_photo),
            "mileage_photo": _file_url(request, inspection.mileage_photo),
            "vin_photo": _file_url(request, inspection.vin_photo),
        },
        "extra_photos": [
            {
                "id": photo.id,
                "image": _file_url(request, photo.image),
                "taken_at": _serialize_datetime(photo.taken_at),
            }
            for photo in inspection.extra_photos.all()
        ],
        "document_pdf": _file_url(request, inspection.document_pdf),
        "photo_taken_at": {
            "application_photo": _serialize_datetime(inspection.application_photo_taken_at),
            "front_photo": _serialize_datetime(inspection.front_photo_taken_at),
            "rear_photo": _serialize_datetime(inspection.rear_photo_taken_at),
            "left_photo": _serialize_datetime(inspection.left_photo_taken_at),
            "right_photo": _serialize_datetime(inspection.right_photo_taken_at),
            "mileage_photo": _serialize_datetime(inspection.mileage_photo_taken_at),
            "vin_photo": _serialize_datetime(inspection.vin_photo_taken_at),
        },
    }


def _serialize_daily_report(report):
    return {
        "id": report.id,
        "report_date": report.report_date.isoformat(),
        "branch": None if report.branch is None else {
            "id": report.branch.id,
            "name": report.branch.name,
        },
        "created_by": None if report.created_by is None else {
            "id": report.created_by.id,
            "login": report.created_by.get_username(),
        },
        "rows": report.rows,
        "total_count": report.total_count,
        "category_counts": report.category_counts,
        "created_at": report.created_at.isoformat(),
        "updated_at": report.updated_at.isoformat(),
    }


def _category_counts_from_rows(rows):
    counts = {}
    for row in rows:
        category = str(row.get("vehicle_category", "")).strip().upper()
        if not category:
            category = "-"
        counts[category] = counts.get(category, 0) + 1
    return counts


def _normalize_vin_text(value):
    return re.sub(r"[^A-Z0-9]", "", value.upper())


def _extract_vin(value):
    normalized = _normalize_vin_text(value)
    if VIN_PATTERN.fullmatch(normalized):
        return normalized

    for candidate in VIN_CANDIDATE_PATTERN.findall(normalized):
        if VIN_PATTERN.fullmatch(candidate):
            return candidate

    return ""


def _build_openai_vin_payload(model, image_inputs, max_output_tokens):
    return {
        "model": model,
        "input": [{
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": (
                        "Read the vehicle VIN from the image. "
                        "Return only JSON with one field named vin. "
                        "The vin value must be exactly 17 characters when readable. "
                        "Allowed characters are A-Z and 0-9, but VIN never contains I, O, or Q. "
                        "If multiple candidates are visible, choose the most likely valid VIN. "
                        "If no VIN is readable, return an empty string in vin."
                    ),
                },
                *image_inputs,
            ],
        }],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "vin_recognition",
                "strict": True,
                "schema": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "vin": {
                            "type": "string",
                            "description": "A 17-character vehicle VIN, or an empty string when unreadable.",
                        },
                    },
                    "required": ["vin"],
                },
            },
        },
        "reasoning": {
            "effort": "low",
        },
        "max_output_tokens": max_output_tokens,
    }


def _collect_openai_text(value):
    chunks = []

    def walk(node):
        if isinstance(node, dict):
            for key, item in node.items():
                if key in {"output_text", "text", "content"} and isinstance(item, str):
                    chunks.append(item)
                else:
                    walk(item)
            return

        if isinstance(node, list):
            for item in node:
                walk(item)

    walk(value)
    return " ".join(chunk.strip() for chunk in chunks if chunk.strip())


def _image_data_url(image_bytes, content_type):
    image_base64 = base64.b64encode(image_bytes).decode("ascii")
    return f"data:{content_type};base64,{image_base64}"


def _enhance_vin_image(image_bytes):
    try:
        image = Image.open(BytesIO(image_bytes))
        image = ImageOps.exif_transpose(image)
        image = image.convert("L")
        image = ImageOps.autocontrast(image, cutoff=1)

        width, height = image.size
        longest_side = max(width, height)
        if longest_side < 1800:
            scale = min(1800 / longest_side, 3)
            image = image.resize(
                (int(width * scale), int(height * scale)),
                Image.Resampling.LANCZOS,
            )

        image = ImageEnhance.Contrast(image).enhance(1.85)
        image = ImageEnhance.Sharpness(image).enhance(2.2)
        image = image.filter(ImageFilter.UnsharpMask(radius=1.2, percent=170, threshold=3))
        image = image.convert("RGB")

        output = BytesIO()
        image.save(output, format="JPEG", quality=94, optimize=True)
        return output.getvalue()
    except Exception:
        return None


def _notify_telegram_inspection_created(request, inspection):
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    if not token or not chat_id:
        return

    operator = "-"
    if inspection.created_by_id:
        operator = inspection.created_by.get_username()

    branch = inspection.branch.name if inspection.branch_id else "-"
    created_at = timezone.localtime(inspection.created_at).strftime("%d.%m.%Y %H:%M")
    admin_url = request.build_absolute_uri(
        f"/admin/inspections/vehicleinspection/{inspection.id}/change/"
    )
    document_url = _file_url(request, inspection.document_pdf)

    lines = [
        "<b>Новый осмотр</b>",
        f"<b>ID:</b> {inspection.id}",
        f"<b>Филиал:</b> {html.escape(branch)}",
        f"<b>Операция:</b> {html.escape(inspection.get_operation_type_display() or '-')}",
        f"<b>Категория:</b> {html.escape(inspection.vehicle_category or '-')}",
        f"<b>Марка:</b> {html.escape(inspection.brand or '-')}",
        f"<b>VIN:</b> {html.escape(inspection.vin or '-')}",
        f"<b>Оператор:</b> {html.escape(operator)}",
        f"<b>Дата:</b> {html.escape(created_at)}",
        f'<a href="{html.escape(admin_url)}">Открыть в админке</a>',
    ]
    if document_url:
        lines.append(f'<a href="{html.escape(document_url)}">Скачать PDF</a>')

    try:
        requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={
                "chat_id": chat_id,
                "text": "\n".join(lines),
                "parse_mode": "HTML",
                "disable_web_page_preview": True,
            },
            timeout=5,
        ).raise_for_status()
    except requests.RequestException as error:
        print(f"Telegram notification failed for inspection {inspection.id}: {error}")


@csrf_exempt
def login_view(request):
    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    data = _json_body(request)
    if data is None:
        return JsonResponse({
            "ok": False,
            "error": "Invalid JSON body",
        }, status=400)

    username = str(data.get("login", data.get("username", ""))).strip()
    password = str(data.get("password", ""))

    user = authenticate(request, username=username, password=password)
    if user is None:
        return JsonResponse({
            "ok": False,
            "error": "Invalid login or password",
        }, status=401)

    if not user.is_active:
        return JsonResponse({
            "ok": False,
            "error": "User is inactive",
        }, status=403)

    login(request, user)
    session_key = request.session.session_key
    profile = _profile_for(user)

    return JsonResponse({
        "ok": True,
        "session_key": session_key,
        "user": {
            "id": user.id,
            "login": user.get_username(),
            "first_name": user.first_name,
            "last_name": user.last_name,
            "full_name": user.get_full_name() or user.get_username(),
            "role": UserProfile.ROLE_ADMIN if user.is_superuser else profile.role,
            "branch": None if profile is None or profile.branch is None else {
                "id": profile.branch.id,
                "name": profile.branch.name,
            },
        },
    })


@csrf_exempt
def logout_view(request):
    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    logout(request)
    return JsonResponse({"ok": True})


def me_view(request):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    profile = _profile_for(user)
    return JsonResponse({
        "ok": True,
        "user": {
            "id": user.id,
            "login": user.get_username(),
            "first_name": user.first_name,
            "last_name": user.last_name,
            "full_name": user.get_full_name() or user.get_username(),
            "role": UserProfile.ROLE_ADMIN if user.is_superuser else profile.role,
            "branch": None if profile is None or profile.branch is None else {
                "id": profile.branch.id,
                "name": profile.branch.name,
            },
        },
    })


def branches_view(request):
    branches = Branch.objects.filter(is_active=True).values("id", "name")
    return JsonResponse({
        "ok": True,
        "branches": list(branches),
    })


@csrf_exempt
def inspections_collection(request):
    if request.method == "GET":
        return inspections_list(request)

    if request.method == "POST":
        return create_inspection(request)

    return JsonResponse({
        "ok": False,
        "error": "Only GET or POST is allowed",
    }, status=405)


@csrf_exempt
def recognize_vin_view(request):
    auth_error, _user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    uploaded_file = request.FILES.get("vin_photo")
    if uploaded_file is None:
        return JsonResponse({
            "ok": False,
            "error": "Field 'vin_photo' is required",
        }, status=400)

    if not _is_image_file(uploaded_file):
        return JsonResponse({
            "ok": False,
            "error": "Uploaded file must be an image",
            "content_type": uploaded_file.content_type,
            "filename": uploaded_file.name,
        }, status=400)

    config = OpenAIApiKey.objects.filter(is_active=True).order_by("-updated_at").first()
    if config is None or not config.api_key.strip():
        return JsonResponse({
            "ok": False,
            "error": "OpenAI API key is not configured",
        }, status=500)

    original_image_bytes = uploaded_file.read()
    enhanced_image_bytes = _enhance_vin_image(original_image_bytes)
    content_type = uploaded_file.content_type or "image/jpeg"
    model = config.model.strip() or "gpt-5.6-terra"
    image_inputs = [
        {
            "type": "input_image",
            "image_url": _image_data_url(original_image_bytes, content_type),
        },
    ]
    if enhanced_image_bytes:
        image_inputs.append({
            "type": "input_image",
            "image_url": _image_data_url(enhanced_image_bytes, "image/jpeg"),
        })

    try:
        response = requests.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {config.api_key.strip()}",
                "Content-Type": "application/json",
            },
            json=_build_openai_vin_payload(model, image_inputs, 2000),
            timeout=45,
        )
    except requests.RequestException as exc:
        return JsonResponse({
            "ok": False,
            "error": f"OpenAI request failed: {exc}",
        }, status=502)

    try:
        data = response.json()
    except ValueError:
        data = {}

    if response.status_code < 200 or response.status_code >= 300:
        message = data.get("error", {}).get("message") if isinstance(data.get("error"), dict) else ""
        return JsonResponse({
            "ok": False,
            "error": message or response.text or "OpenAI returned an error",
        }, status=502)

    raw_text = _collect_openai_text(data)

    vin = _extract_vin(raw_text)
    if not vin:
        output_types = [
            item.get("type", "")
            for item in data.get("output", [])
            if isinstance(item, dict)
        ]
        return JsonResponse({
            "ok": False,
            "error": "VIN was not recognized",
            "raw_text": raw_text,
            "output_types": output_types,
        }, status=422)

    return JsonResponse({
        "ok": True,
        "vin": vin,
        "raw_text": raw_text,
    })


def inspections_list(request):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    query = request.GET.get("q", "").strip()
    vin_query = request.GET.get("vin", "").strip().upper()
    queryset = _allowed_inspections(user)

    if vin_query:
        queryset = queryset.filter(vin__icontains=vin_query)
    else:
        start, end, error = _date_range(request)
        if error is not None:
            return error

        queryset = queryset.filter(created_at__gte=start, created_at__lt=end)

    if query:
        queryset = queryset.filter(
            brand__icontains=query
        ) | queryset.filter(
            country__icontains=query
        ) | queryset.filter(
            plate_number__icontains=query
        ) | queryset.filter(
            vin__icontains=query
        )

    return JsonResponse({
        "ok": True,
        "inspections": [
            _serialize_inspection(request, inspection)
            for inspection in queryset.order_by("-created_at")[:300]
        ],
    })


def inspection_detail(request, inspection_id):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    inspection = _allowed_inspections(user).filter(id=inspection_id).first()
    if inspection is None:
        return JsonResponse({
            "ok": False,
            "error": "Inspection not found",
        }, status=404)

    return JsonResponse({
        "ok": True,
        "inspection": _serialize_inspection(request, inspection),
    })


def reports_summary(request):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    if not _is_report_user(user):
        return JsonResponse({
            "ok": False,
            "error": "Reports access denied",
        }, status=403)

    start, end, error = _date_range(request)
    if error is not None:
        return error

    queryset = _allowed_inspections(user).filter(created_at__gte=start, created_at__lt=end)
    branch_counts = queryset.values("branch_id", "branch__name").annotate(
        inspections_count=Count("id")
    ).order_by("branch__name")

    today = timezone.localdate()
    week_start = today - timedelta(days=6)
    month_start = today.replace(day=1)
    base = _allowed_inspections(user)

    return JsonResponse({
        "ok": True,
        "period": {
            "date_from": start.date().isoformat(),
            "date_to": (end - timedelta(days=1)).date().isoformat(),
        },
        "totals": {
            "period": queryset.count(),
            "today": base.filter(created_at__date=today).count(),
            "week": base.filter(created_at__date__gte=week_start).count(),
            "month": base.filter(created_at__date__gte=month_start).count(),
        },
        "branches": [
            {
                "id": item["branch_id"],
                "name": item["branch__name"] or "Без филиала",
                "inspections_count": item["inspections_count"],
            }
            for item in branch_counts
        ],
    })


@csrf_exempt
def daily_reports_collection(request):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    if not _is_report_user(user):
        return JsonResponse({
            "ok": False,
            "error": "Reports access denied",
        }, status=403)

    if request.method == "GET":
        return daily_reports_list(request, user)

    if request.method == "POST":
        return create_daily_report(request, user)

    return JsonResponse({
        "ok": False,
        "error": "Only GET or POST is allowed",
    }, status=405)


def daily_reports_list(request, user):
    start, end, error = _date_range(request)
    if error is not None:
        return error

    reports = DailyInspectionReport.objects.select_related("branch", "created_by").filter(
        report_date__gte=start.date(),
        report_date__lt=end.date(),
    )

    profile = _profile_for(user)
    if not user.is_superuser and profile.role != UserProfile.ROLE_ADMIN:
        if profile.branch_id is None:
            reports = reports.filter(branch__isnull=True)
        else:
            reports = reports.filter(branch_id=profile.branch_id)

    return JsonResponse({
        "ok": True,
        "reports": [
            _serialize_daily_report(report)
            for report in reports.order_by("-report_date", "branch__name")[:300]
        ],
    })


def create_daily_report(request, user):
    body = _json_body(request)
    if body is None:
        return JsonResponse({
            "ok": False,
            "error": "Invalid JSON body",
        }, status=400)

    report_date_raw = str(body.get("report_date", "")).strip()
    try:
        report_date = (
            datetime.strptime(report_date_raw, "%Y-%m-%d").date()
            if report_date_raw
            else timezone.localdate()
        )
    except ValueError:
        return JsonResponse({
            "ok": False,
            "error": "Field 'report_date' must be YYYY-MM-DD",
        }, status=400)

    profile = _profile_for(user)
    branch = profile.branch
    branch_id = body.get("branch_id")
    if branch_id and (user.is_superuser or profile.role == UserProfile.ROLE_ADMIN):
        branch = Branch.objects.filter(id=branch_id, is_active=True).first()
        if branch is None:
            return JsonResponse({
                "ok": False,
                "error": "Branch not found",
            }, status=404)

    raw_rows = body.get("rows")
    if not isinstance(raw_rows, list):
        return JsonResponse({
            "ok": False,
            "error": "Field 'rows' must be a list",
        }, status=400)

    allowed_ids = set(
        _allowed_inspections(user)
        .filter(created_at__date=report_date)
        .values_list("id", flat=True)
    )
    rows = []
    for raw_row in raw_rows:
        if not isinstance(raw_row, dict):
            continue

        inspection_id = raw_row.get("inspection_id")
        try:
            inspection_id = int(inspection_id)
        except (TypeError, ValueError):
            continue

        if inspection_id not in allowed_ids:
            continue

        category = str(raw_row.get("vehicle_category", "")).strip().upper()
        if category not in dict(VehicleInspection.CATEGORY_CHOICES):
            category = ""

        rows.append({
            "inspection_id": inspection_id,
            "brand": str(raw_row.get("brand", "")).strip()[:160],
            "vehicle_category": category,
            "vin": str(raw_row.get("vin", "")).strip().upper()[:17],
            "number": str(raw_row.get("number", "")).strip()[:80],
            "talon_number": str(raw_row.get("talon_number", "")).strip()[:80],
        })

    category_counts = _category_counts_from_rows(rows)
    report, _created = DailyInspectionReport.objects.update_or_create(
        report_date=report_date,
        branch=branch,
        defaults={
            "created_by": user,
            "rows": rows,
            "total_count": len(rows),
            "category_counts": category_counts,
        },
    )

    return JsonResponse({
        "ok": True,
        "report": _serialize_daily_report(report),
    }, status=201)


@csrf_exempt
def create_inspection(request):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    title = request.POST.get("title", "").strip()
    operation_type = request.POST.get(
        "operation_type",
        VehicleInspection.OPERATION_SBGTS,
    ).strip()
    plate_number = request.POST.get("plate_number", "").strip().upper()
    brand = request.POST.get("brand", "").strip()
    country = request.POST.get("country", "").strip()
    vin = request.POST.get("vin", "").strip().upper()
    vehicle_category = request.POST.get("vehicle_category", VehicleInspection.CATEGORY_M1).strip().upper()
    profile = getattr(user, "profile", None)
    branch = None if profile is None else profile.branch

    if not brand:
        return JsonResponse({"ok": False, "error": "Field 'brand' is required"}, status=400)

    if not vin:
        return JsonResponse({"ok": False, "error": "Field 'vin' is required"}, status=400)

    if vehicle_category not in dict(VehicleInspection.CATEGORY_CHOICES):
        return JsonResponse({
            "ok": False,
            "error": "Field 'vehicle_category' must be M1, M2, M3, N1, N2 or N3",
        }, status=400)

    if operation_type not in dict(VehicleInspection.OPERATION_CHOICES):
        return JsonResponse({
            "ok": False,
            "error": "Field 'operation_type' is invalid",
        }, status=400)

    if not title:
        title = f"{brand} {plate_number}".strip() or "Осмотр авто"

    if branch is None:
        return JsonResponse({
            "ok": False,
            "error": "User branch is not selected",
        }, status=400)

    invalid_photos = []
    for field in REQUIRED_PHOTO_FIELDS:
        uploaded_file = request.FILES.get(field)
        if uploaded_file is None:
            continue

        if not _is_image_file(uploaded_file):
            invalid_photos.append({
                "field": field,
                "filename": uploaded_file.name,
                "content_type": uploaded_file.content_type,
            })

    conversion_photos = request.FILES.getlist("conversion_photos")
    if len(conversion_photos) > 12:
        return JsonResponse({
            "ok": False,
            "error": "No more than 12 conversion photos are allowed",
        }, status=400)

    for index, uploaded_file in enumerate(conversion_photos):
        if not _is_image_file(uploaded_file):
            invalid_photos.append({
                "field": "conversion_photos",
                "index": index,
                "filename": uploaded_file.name,
                "content_type": uploaded_file.content_type,
            })

    if invalid_photos:
        return JsonResponse({
            "ok": False,
            "error": "All uploaded files must be images",
            "invalid_photos": invalid_photos,
        }, status=400)

    document_pdf = request.FILES.get("document_pdf")
    if document_pdf is not None and document_pdf.content_type != "application/pdf":
        return JsonResponse({
            "ok": False,
            "error": "Uploaded document must be a PDF",
            "content_type": document_pdf.content_type,
        }, status=400)

    photo_taken_at = {
        field: _parse_photo_taken_at(request.POST.get(f"{field}_taken_at", ""))
        for field in REQUIRED_PHOTO_FIELDS
    }

    inspection = VehicleInspection.objects.create(
        title=title,
        operation_type=operation_type,
        plate_number=plate_number,
        brand=brand,
        country=country,
        vehicle_category=vehicle_category,
        branch=branch,
        created_by=user,
        vin=vin,
        application_photo=request.FILES.get("application_photo"),
        front_photo=request.FILES.get("front_photo"),
        rear_photo=request.FILES.get("rear_photo"),
        left_photo=request.FILES.get("left_photo"),
        right_photo=request.FILES.get("right_photo"),
        mileage_photo=request.FILES.get("mileage_photo"),
        vin_photo=request.FILES.get("vin_photo"),
        document_pdf=document_pdf,
        application_photo_taken_at=photo_taken_at["application_photo"],
        front_photo_taken_at=photo_taken_at["front_photo"],
        rear_photo_taken_at=photo_taken_at["rear_photo"],
        left_photo_taken_at=photo_taken_at["left_photo"],
        right_photo_taken_at=photo_taken_at["right_photo"],
        mileage_photo_taken_at=photo_taken_at["mileage_photo"],
        vin_photo_taken_at=photo_taken_at["vin_photo"],
    )
    _notify_telegram_inspection_created(request, inspection)

    conversion_photo_taken_at = _parse_photo_taken_at(
        request.POST.get("conversion_photos_taken_at", "")
    )
    for uploaded_file in conversion_photos:
        VehicleInspectionExtraPhoto.objects.create(
            inspection=inspection,
            image=uploaded_file,
            taken_at=conversion_photo_taken_at,
        )

    return JsonResponse({
        "ok": True,
        "id": inspection.id,
        "title": inspection.title,
        "operation_type": inspection.operation_type,
        "operation_type_label": inspection.get_operation_type_display(),
        "plate_number": inspection.plate_number,
        "brand": inspection.brand,
        "country": inspection.country,
        "vehicle_category": inspection.vehicle_category,
        "vin": inspection.vin,
        "document_pdf": _file_url(request, inspection.document_pdf),
        "branch": {
            "id": branch.id,
            "name": branch.name,
        },
        "admin_url": f"/admin/inspections/vehicleinspection/{inspection.id}/change/",
    }, status=201)


def _is_image_file(uploaded_file):
    suffix = uploaded_file.name.rsplit(".", 1)[-1].lower() if "." in uploaded_file.name else ""
    is_image_extension = f".{suffix}" in IMAGE_EXTENSIONS
    is_image_content_type = uploaded_file.content_type.startswith("image/")
    return is_image_content_type or is_image_extension


def _parse_photo_taken_at(raw_value):
    if not raw_value:
        return None

    value = parse_datetime(raw_value)
    if value is None:
        return None

    if timezone.is_naive(value):
        value = timezone.make_aware(value, timezone.get_current_timezone())

    return value
