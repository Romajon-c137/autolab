import base64
from datetime import datetime, timedelta
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
import requests

from .models import AiApiKey, Branch, UserProfile, VehicleInspection

REQUIRED_PHOTO_FIELDS = (
    "front_photo",
    "rear_photo",
    "left_photo",
    "right_photo",
    "mileage_photo",
    "vin_photo",
)
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}
VIN_PATTERN = re.compile(r"\b[A-HJ-NPR-Z0-9]{17}\b")


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
    queryset = VehicleInspection.objects.select_related("branch", "created_by")

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
            "front_photo": _file_url(request, inspection.front_photo),
            "rear_photo": _file_url(request, inspection.rear_photo),
            "left_photo": _file_url(request, inspection.left_photo),
            "right_photo": _file_url(request, inspection.right_photo),
            "mileage_photo": _file_url(request, inspection.mileage_photo),
            "vin_photo": _file_url(request, inspection.vin_photo),
        },
        "document_pdf": _file_url(request, inspection.document_pdf),
        "photo_taken_at": {
            "front_photo": _serialize_datetime(inspection.front_photo_taken_at),
            "rear_photo": _serialize_datetime(inspection.rear_photo_taken_at),
            "left_photo": _serialize_datetime(inspection.left_photo_taken_at),
            "right_photo": _serialize_datetime(inspection.right_photo_taken_at),
            "mileage_photo": _serialize_datetime(inspection.mileage_photo_taken_at),
            "vin_photo": _serialize_datetime(inspection.vin_photo_taken_at),
        },
    }


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


def inspections_list(request):
    auth_error, user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    start, end, error = _date_range(request)
    if error is not None:
        return error

    query = request.GET.get("q", "").strip()
    queryset = _allowed_inspections(user).filter(created_at__gte=start, created_at__lt=end)

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
def recognize_vin(request):
    auth_error, _user = _require_auth(request)
    if auth_error is not None:
        return auth_error

    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    image = request.FILES.get("vin_photo")
    if image is None:
        return JsonResponse({
            "ok": False,
            "error": "Field 'vin_photo' is required",
        }, status=400)

    if not _is_image_file(image):
        return JsonResponse({
            "ok": False,
            "error": "Uploaded file must be an image",
            "content_type": image.content_type,
            "filename": image.name,
        }, status=400)

    ai_key = AiApiKey.objects.filter(is_active=True).first()
    api_key = ai_key.api_key if ai_key is not None else os.environ.get("OPENAI_API_KEY")
    model = (
        ai_key.model
        if ai_key is not None and ai_key.model
        else os.environ.get("OPENAI_VIN_MODEL", "gpt-5.6")
    )

    if not api_key:
        return JsonResponse({
            "ok": False,
            "error": "OpenAI API key is not configured. Add active AI API key in admin.",
        }, status=503)

    image.seek(0)
    mime_type = _image_mime_type(image)
    image_data = base64.b64encode(image.read()).decode("ascii")

    try:
        response = requests.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "input": [{
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": (
                                "Read the vehicle VIN from this image. "
                                "Return only JSON: {\"vin\":\"...\"}. "
                                "VIN must be exactly 17 characters, uppercase, "
                                "and must not contain I, O, or Q. If unreadable, "
                                "return {\"vin\":\"\"}."
                            ),
                        },
                        {
                            "type": "input_image",
                            "image_url": f"data:{mime_type};base64,{image_data}",
                        },
                    ],
                }],
            },
            timeout=30,
        )
    except requests.RequestException as error:
        return JsonResponse({
            "ok": False,
            "error": "OpenAI request failed",
            "details": str(error),
        }, status=502)

    if response.status_code < 200 or response.status_code >= 300:
        return JsonResponse({
            "ok": False,
            "error": "OpenAI returned an error",
            "status_code": response.status_code,
            "details": response.text,
        }, status=502)

    data = response.json()
    output_text = _extract_openai_output_text(data)
    vin = _extract_vin(output_text)

    return JsonResponse({
        "ok": True,
        "vin": vin,
        "raw": output_text,
        "model": model,
    })


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
    plate_number = request.POST.get("plate_number", "").strip().upper()
    brand = request.POST.get("brand", "").strip()
    country = request.POST.get("country", "").strip()
    vehicle_category = request.POST.get("vehicle_category", VehicleInspection.CATEGORY_M1).strip().upper()
    profile = getattr(user, "profile", None)
    branch = None if profile is None else profile.branch

    if not brand:
        return JsonResponse({"ok": False, "error": "Field 'brand' is required"}, status=400)

    if vehicle_category not in dict(VehicleInspection.CATEGORY_CHOICES):
        return JsonResponse({
            "ok": False,
            "error": "Field 'vehicle_category' must be M1 or N1",
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
        plate_number=plate_number,
        brand=brand,
        country=country,
        vehicle_category=vehicle_category,
        branch=branch,
        created_by=user,
        vin=request.POST.get("vin", "").strip().upper(),
        front_photo=request.FILES.get("front_photo"),
        rear_photo=request.FILES.get("rear_photo"),
        left_photo=request.FILES.get("left_photo"),
        right_photo=request.FILES.get("right_photo"),
        mileage_photo=request.FILES.get("mileage_photo"),
        vin_photo=request.FILES.get("vin_photo"),
        document_pdf=document_pdf,
        front_photo_taken_at=photo_taken_at["front_photo"],
        rear_photo_taken_at=photo_taken_at["rear_photo"],
        left_photo_taken_at=photo_taken_at["left_photo"],
        right_photo_taken_at=photo_taken_at["right_photo"],
        mileage_photo_taken_at=photo_taken_at["mileage_photo"],
        vin_photo_taken_at=photo_taken_at["vin_photo"],
    )
    _notify_telegram_inspection_created(request, inspection)

    return JsonResponse({
        "ok": True,
        "id": inspection.id,
        "title": inspection.title,
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


def _image_mime_type(uploaded_file):
    if uploaded_file.content_type.startswith("image/"):
        return uploaded_file.content_type

    suffix = uploaded_file.name.rsplit(".", 1)[-1].lower() if "." in uploaded_file.name else ""
    return {
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "gif": "image/gif",
        "webp": "image/webp",
        "heic": "image/heic",
        "heif": "image/heif",
    }.get(suffix, "image/jpeg")


def _extract_openai_output_text(data):
    if isinstance(data.get("output_text"), str):
        return data["output_text"]

    chunks = []
    for output in data.get("output", []):
        for content in output.get("content", []):
            text = content.get("text")
            if isinstance(text, str):
                chunks.append(text)
    return "\n".join(chunks)


def _extract_vin(text):
    try:
        parsed = json.loads(text)
        value = str(parsed.get("vin", "")).upper()
    except (json.JSONDecodeError, AttributeError):
        value = text.upper()

    value = value.replace(" ", "").replace("-", "")
    match = VIN_PATTERN.search(value)
    return "" if match is None else match.group(0)
