from datetime import datetime, timedelta
import base64
from io import BytesIO
import json
import os
import re
import secrets

from django.contrib.auth import authenticate, login, logout
from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Count
from django.http import JsonResponse
from django.utils.dateparse import parse_datetime
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from PIL import Image, ImageEnhance, ImageFilter, ImageOps
import requests

from .access import (
    allowed_inspections,
    date_range,
    is_report_user,
    profile_for,
    require_auth,
)
from .application_pdfs import (
    link_application_on_inspection_created,
    link_application_on_submit,
    save_client_application,
)
from .models import (
    Branch,
    ClientApplication,
    InspectionPrice,
    OpenAIApiKey,
    UserProfile,
    VehicleInspection,
    VehicleInspectionExtraPhoto,
)
from .notifications import notify_telegram_inspection_created
from .serializers import (
    file_url,
    serialize_application,
    serialize_inspection,
)
from .security import (
    UploadValidationError,
    inspection_fingerprint,
    rate_limit,
    validate_image,
    validate_pdf,
)
from .storage_mirror import mirror_inspection
from .two_factor import (
    TwoFactorError,
    create_login_challenge,
    mask_phone,
    verify_login_challenge,
)

REQUIRED_PHOTO_FIELDS = (
    "front_photo",
    "rear_photo",
    "left_photo",
    "right_photo",
    "mileage_photo",
    "vin_photo",
)
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}
VIN_PATTERN = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
VEHICLE_IDENTIFIER_PATTERN = re.compile(r"^[A-Z0-9-]{1,32}$")
VIN_CANDIDATE_PATTERN = re.compile(r"[A-HJ-NPR-Z0-9]{17}")
MILEAGE_CANDIDATE_PATTERN = re.compile(r"\d{1,8}")
KNOWN_WMI_PREFIXES = (
    "KLY",
    "XUU",
    "JT",
    "JH",
    "JM",
    "JN",
    "KL",
    "KM",
    "KN",
    "W0",
    "WA",
    "WB",
    "WD",
    "WF",
    "WVW",
    "ZFA",
)


def _serialize_user(user):
    profile = profile_for(user)
    return {
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
    }


def _json_body(request):
    if not request.body:
        return {}

    try:
        return json.loads(request.body.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def _normalize_vin_text(value):
    return re.sub(r"[^A-Z0-9]", "", value.upper())


def _extract_vin(value):
    normalized = _normalize_vin_text(value)
    if VIN_PATTERN.fullmatch(normalized):
        return normalized

    candidates = [
        normalized[index:index + 17]
        for index in range(max(len(normalized) - 16, 0))
        if VIN_PATTERN.fullmatch(normalized[index:index + 17])
    ]
    if not candidates:
        return ""

    for candidate in candidates:
        if candidate.startswith(KNOWN_WMI_PREFIXES):
            return candidate

    if len(normalized) > 17:
        for candidate in candidates:
            if not candidate.startswith("N"):
                return candidate

    return candidates[0]


def _extract_mileage(value):
    candidates = MILEAGE_CANDIDATE_PATTERN.findall(value.replace(" ", ""))
    if not candidates:
        return ""

    return max(candidates, key=len)


def _build_openai_vin_payload(model, image_inputs, max_output_tokens):
    return {
        "model": model,
        "input": [{
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": (
                        "Read the vehicle VIN from the photos. Return JSON only: {\"vin\":\"...\"}. "
                        "Use the original photo as the source of truth. "
                        "VIN is exactly 17 chars, A-Z/0-9, never I/O/Q. "
                        "Read the 17 physical character positions left-to-right; do not add a prefix. "
                        "Ignore any isolated leading scratch, star, cross, seam, bolt, border, or stamped mark "
                        "that is not aligned with the 17 VIN characters. "
                        "The first 3 characters are the WMI manufacturer identifier, and character 1 is a "
                        "country/region code. Common first characters in imported vehicles include X, J, K, L, "
                        "W, Z, S, V, T, M, R, digits 1-5, 6, 7, 8, and 9. "
                        "N is possible only in specific real WMI codes, not as a default correction. "
                        "Never convert an unclear left edge, shadow, screw, border, or partial vertical mark into N. "
                        "Use N as the first character only if a complete printed N is clearly visible: left vertical, "
                        "diagonal stroke, and right vertical. "
                        "If adding N at the front makes 17 characters while the visible code after it has only 16, "
                        "this is probably a hallucinated prefix; return empty string instead. "
                        "Do not compensate for a guessed first N by dropping the last character. "
                        "Do not guess or invent missing characters. "
                        "Only return a VIN when all 17 characters are visible enough to read. "
                        "If any character is unclear, hidden, cut off, or ambiguous, use empty string."
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
        "max_output_tokens": max_output_tokens,
    }


def _build_openai_mileage_payload(model, image_inputs, max_output_tokens):
    return {
        "model": model,
        "input": [{
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": (
                        "Read odometer mileage digits only. "
                        "Ignore labels, km, trip, time/date, icons. "
                        "Return JSON only: {\"mileage\":\"123456\"}. "
                        "If unreadable, use empty string."
                    ),
                },
                *image_inputs,
            ],
        }],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "mileage_recognition",
                "strict": True,
                "schema": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "mileage": {
                            "type": "string",
                            "description": "Dashboard odometer mileage digits, or an empty string when unreadable.",
                        },
                    },
                    "required": ["mileage"],
                },
            },
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


def _single_ocr_image_input(original_image_bytes, content_type):
    enhanced_image_bytes = _enhance_vin_image(original_image_bytes)
    if enhanced_image_bytes:
        return [{
            "type": "input_image",
            "image_url": _image_data_url(enhanced_image_bytes, "image/jpeg"),
        }]

    return [{
        "type": "input_image",
        "image_url": _image_data_url(original_image_bytes, content_type or "image/jpeg"),
    }]


def _vin_ocr_image_inputs(original_image_bytes, content_type):
    return [{
        "type": "input_image",
        "image_url": _image_data_url(original_image_bytes, content_type or "image/jpeg"),
    }]


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


@csrf_exempt
def login_view(request):
    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    if not rate_limit(request, "login", 10, 300):
        return JsonResponse({"ok": False, "error": "Too many login attempts"}, status=429)

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

    profile = profile_for(user)
    if not profile.can_use_app:
        return JsonResponse({
            "ok": False,
            "error": "Пользователю запрещен вход в приложение.",
        }, status=403)

    if not profile.phone_number.strip():
        return JsonResponse({
            "ok": False,
            "error": "У пользователя не указан телефон WhatsApp для входа.",
        }, status=403)

    try:
        challenge, debug_code = create_login_challenge(user)
    except TwoFactorError as error:
        return JsonResponse({
            "ok": False,
            "error": str(error),
        }, status=502)

    response = {
        "ok": True,
        "two_factor_required": True,
        "challenge_id": str(challenge.challenge_id),
        "phone_masked": mask_phone(profile.phone_number),
        "expires_in": int((challenge.expires_at - timezone.now()).total_seconds()),
    }
    if debug_code is not None:
        response["debug_code"] = debug_code
    return JsonResponse(response)


@csrf_exempt
def verify_two_factor_view(request):
    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    if not rate_limit(request, "verify-2fa", 20, 300):
        return JsonResponse({"ok": False, "error": "Too many verification attempts"}, status=429)

    data = _json_body(request)
    if data is None:
        return JsonResponse({
            "ok": False,
            "error": "Invalid JSON body",
        }, status=400)

    challenge_id = str(data.get("challenge_id", "")).strip()
    code = str(data.get("code", "")).strip()
    if not challenge_id or not code:
        return JsonResponse({
            "ok": False,
            "error": "challenge_id and code are required",
        }, status=400)

    try:
        user = verify_login_challenge(challenge_id, code)
    except TwoFactorError as error:
        return JsonResponse({
            "ok": False,
            "error": str(error),
        }, status=422)

    if not user.is_active:
        return JsonResponse({
            "ok": False,
            "error": "User is inactive",
        }, status=403)

    login(request, user)
    session_key = request.session.session_key

    return JsonResponse({
        "ok": True,
        "session_key": session_key,
        "user": _serialize_user(user),
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
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error

    return JsonResponse({
        "ok": True,
        "user": _serialize_user(user),
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
    auth_error, _user = require_auth(request)
    if auth_error is not None:
        return auth_error
    if not rate_limit(request, "recognize-vin", 10, 60):
        return JsonResponse({"ok": False, "error": "Too many requests"}, status=429)

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

    try:
        validate_image(uploaded_file)
    except UploadValidationError as error:
        return JsonResponse({
            "ok": False,
            "error": str(error),
        }, status=400)

    config = OpenAIApiKey.objects.filter(is_active=True).order_by("-updated_at").first()
    if config is None or not config.api_key.strip():
        return JsonResponse({
            "ok": False,
            "error": "OpenAI API key is not configured",
        }, status=500)

    original_image_bytes = uploaded_file.read()
    content_type = uploaded_file.content_type or "image/jpeg"
    model = os.environ.get("OPENAI_VIN_MODEL", "gpt-4o-mini").strip() or "gpt-4o-mini"
    image_inputs = _vin_ocr_image_inputs(original_image_bytes, content_type)

    try:
        response = requests.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {config.api_key.strip()}",
                "Content-Type": "application/json",
            },
            json=_build_openai_vin_payload(model, image_inputs, 120),
            timeout=45,
        )
    except requests.RequestException as exc:
        return JsonResponse({"ok": False, "error": "Recognition service is unavailable"}, status=502)

    try:
        data = response.json()
    except ValueError:
        data = {}

    if response.status_code < 200 or response.status_code >= 300:
        return JsonResponse({
            "ok": False,
            "error": "Recognition service returned an error",
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


@csrf_exempt
def recognize_mileage_view(request):
    auth_error, _user = require_auth(request)
    if auth_error is not None:
        return auth_error
    if not rate_limit(request, "recognize-mileage", 10, 60):
        return JsonResponse({"ok": False, "error": "Too many requests"}, status=429)

    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    uploaded_file = request.FILES.get("mileage_photo")
    if uploaded_file is None:
        return JsonResponse({
            "ok": False,
            "error": "Field 'mileage_photo' is required",
        }, status=400)

    try:
        validate_image(uploaded_file)
    except UploadValidationError as error:
        return JsonResponse({
            "ok": False,
            "error": str(error),
        }, status=400)

    config = OpenAIApiKey.objects.filter(is_active=True).order_by("-updated_at").first()
    if config is None or not config.api_key.strip():
        return JsonResponse({
            "ok": False,
            "error": "OpenAI API key is not configured",
        }, status=500)

    original_image_bytes = uploaded_file.read()
    content_type = uploaded_file.content_type or "image/jpeg"
    model = os.environ.get("OPENAI_MILEAGE_MODEL", "gpt-4o-mini").strip() or "gpt-4o-mini"
    image_inputs = _single_ocr_image_input(original_image_bytes, content_type)

    try:
        response = requests.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {config.api_key.strip()}",
                "Content-Type": "application/json",
            },
            json=_build_openai_mileage_payload(model, image_inputs, 60),
            timeout=45,
        )
    except requests.RequestException as exc:
        return JsonResponse({"ok": False, "error": "Recognition service is unavailable"}, status=502)

    try:
        data = response.json()
    except ValueError:
        data = {}

    if response.status_code < 200 or response.status_code >= 300:
        return JsonResponse({
            "ok": False,
            "error": "Recognition service returned an error",
        }, status=502)

    raw_text = _collect_openai_text(data)
    mileage = _extract_mileage(raw_text)
    if not mileage:
        output_types = [
            item.get("type", "")
            for item in data.get("output", [])
            if isinstance(item, dict)
        ]
        return JsonResponse({
            "ok": False,
            "error": "Mileage was not recognized",
            "raw_text": raw_text,
            "output_types": output_types,
        }, status=422)

    return JsonResponse({
        "ok": True,
        "mileage": mileage,
        "raw_text": raw_text,
    })


def inspections_list(request):
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error

    query = request.GET.get("q", "").strip()
    vin_query = request.GET.get("vin", "").strip().upper()
    queryset = allowed_inspections(user)

    if vin_query:
        queryset = queryset.filter(vin__icontains=vin_query)
    else:
        start, end, error = date_range(request)
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
            serialize_inspection(request, inspection)
            for inspection in queryset.order_by("-created_at")[:300]
        ],
    })


def inspection_detail(request, inspection_id):
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error

    inspection = allowed_inspections(user).filter(id=inspection_id).first()
    if inspection is None:
        return JsonResponse({
            "ok": False,
            "error": "Inspection not found",
        }, status=404)

    return JsonResponse({
        "ok": True,
        "inspection": serialize_inspection(request, inspection),
    })


def reports_summary(request):
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error

    if not is_report_user(user):
        return JsonResponse({
            "ok": False,
            "error": "Reports access denied",
        }, status=403)

    start, end, error = date_range(request)
    if error is not None:
        return error

    queryset = allowed_inspections(user).filter(created_at__gte=start, created_at__lt=end)
    branch_counts = queryset.values("branch_id", "branch__name").annotate(
        inspections_count=Count("id")
    ).order_by("branch__name")

    today = timezone.localdate()
    week_start = today - timedelta(days=6)
    month_start = today.replace(day=1)
    base = allowed_inspections(user)

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


def _current_inspection_amount(operation_type, vehicle_category):
    price_category = (
        vehicle_category
        if operation_type in {
            VehicleInspection.OPERATION_TECH_INSPECTION,
            VehicleInspection.OPERATION_SBGTS,
        }
        else ""
    )
    price = (
        InspectionPrice.objects.filter(
            operation_type=operation_type,
            vehicle_category=price_category,
            is_active=True,
            effective_from__lte=timezone.localdate(),
        )
        .order_by("-effective_from", "-id")
        .first()
    )
    return 0 if price is None else price.amount


@csrf_exempt
def client_application_submit(request):
    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    expected_key = settings.CLIENT_APPLICATION_API_KEY
    supplied_key = request.headers.get("X-Client-Application-Key", "")
    if not expected_key or not secrets.compare_digest(supplied_key, expected_key):
        return JsonResponse({"ok": False, "error": "Authentication required"}, status=401)
    if not rate_limit(request, "client-application", 10, 300):
        return JsonResponse({"ok": False, "error": "Too many requests"}, status=429)

    vin = _normalize_vin_text(request.POST.get("vin", ""))
    if not VIN_PATTERN.match(vin):
        return JsonResponse({
            "ok": False,
            "error": "Field 'vin' must be a valid 17-character VIN",
        }, status=400)

    applicant_name = request.POST.get("applicant_name", "").strip()[:200]
    inn = request.POST.get("inn", "").strip()[:20]
    phone = request.POST.get("phone", "").strip()[:32]
    vehicle_name = request.POST.get("vehicle_name", "").strip()[:120]
    plate_number = request.POST.get("plate_number", "").strip()[:20]
    year = request.POST.get("year", "").strip()[:10]

    uploaded_pdf = request.FILES.get("application_pdf")
    if uploaded_pdf is None:
        return JsonResponse({
            "ok": False,
            "error": "Field 'application_pdf' is required",
        }, status=400)

    try:
        validate_pdf(uploaded_pdf)
    except UploadValidationError as error:
        return JsonResponse({
            "ok": False,
            "error": str(error),
        }, status=400)

    application = save_client_application(
        vin,
        applicant_name,
        inn,
        phone,
        vehicle_name,
        plate_number,
        year,
        uploaded_pdf,
    )
    inspection = link_application_on_submit(application)
    if inspection is not None:
        mirror_inspection(inspection)

    return JsonResponse({
        "ok": True,
        "application": serialize_application(request, application),
        "inspection": None if inspection is None else serialize_inspection(request, inspection),
    })


def client_applications_list(request):
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error

    queryset = ClientApplication.objects.select_related("inspection")

    vin_query = request.GET.get("vin", "").strip().upper()
    query = request.GET.get("q", "").strip()

    if vin_query or query:
        if vin_query:
            queryset = queryset.filter(vin__icontains=vin_query)
        if query:
            queryset = queryset.filter(
                applicant_name__icontains=query
            ) | queryset.filter(
                inn__icontains=query
            ) | queryset.filter(
                phone__icontains=query
            ) | queryset.filter(
                vin__icontains=query
            )
    else:
        start, end, error = date_range(request)
        if error is not None:
            return error

        queryset = queryset.filter(created_at__gte=start, created_at__lt=end)

    return JsonResponse({
        "ok": True,
        "applications": [
            serialize_application(request, application)
            for application in queryset.order_by("-created_at")[:300]
        ],
    })


@csrf_exempt
def create_inspection(request):
    auth_error, user = require_auth(request)
    if auth_error is not None:
        return auth_error
    if not rate_limit(request, "create-inspection", 30, 60):
        return JsonResponse({"ok": False, "error": "Too many requests"}, status=429)

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

    if not VEHICLE_IDENTIFIER_PATTERN.fullmatch(vin):
        return JsonResponse({"ok": False, "error": "Field 'vin' has an invalid format"}, status=400)

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

        try:
            validate_image(uploaded_file)
        except UploadValidationError as error:
            invalid_photos.append({
                "field": field,
                "error": str(error),
            })

    conversion_photos = request.FILES.getlist("conversion_photos")
    if len(conversion_photos) > 12:
        return JsonResponse({
            "ok": False,
            "error": "No more than 12 conversion photos are allowed",
        }, status=400)

    for index, uploaded_file in enumerate(conversion_photos):
        try:
            validate_image(uploaded_file)
        except UploadValidationError as error:
            invalid_photos.append({
                "field": "conversion_photos",
                "index": index,
                "error": str(error),
            })

    if invalid_photos:
        return JsonResponse({
            "ok": False,
            "error": "All uploaded files must be images",
            "invalid_photos": invalid_photos,
        }, status=400)

    document_pdf = request.FILES.get("document_pdf")
    if document_pdf is not None:
        try:
            validate_pdf(document_pdf)
        except UploadValidationError as error:
            return JsonResponse({"ok": False, "error": str(error)}, status=400)

    photo_taken_at = {
        field: _parse_photo_taken_at(request.POST.get(f"{field}_taken_at", ""))
        for field in REQUIRED_PHOTO_FIELDS
    }

    fingerprint = inspection_fingerprint(
        user.id,
        (title, operation_type, plate_number, brand, country, vehicle_category, vin),
        [request.FILES.get(field) for field in REQUIRED_PHOTO_FIELDS]
        + list(conversion_photos)
        + [document_pdf],
    )

    try:
        with transaction.atomic():
            existing = VehicleInspection.objects.filter(request_fingerprint=fingerprint).first()
            if existing is not None:
                return _inspection_created_response(request, existing, status=200, duplicate=True)

            inspection = VehicleInspection.objects.create(
                title=title,
                operation_type=operation_type,
                plate_number=plate_number,
                brand=brand,
                country=country,
                vehicle_category=vehicle_category,
                amount=_current_inspection_amount(operation_type, vehicle_category),
                branch=branch,
                created_by=user,
                vin=vin,
                request_fingerprint=fingerprint,
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

            conversion_photo_taken_at = _parse_photo_taken_at(
                request.POST.get("conversion_photos_taken_at", "")
            )
            for uploaded_file in conversion_photos:
                VehicleInspectionExtraPhoto.objects.create(
                    inspection=inspection,
                    image=uploaded_file,
                    taken_at=conversion_photo_taken_at,
                )
            link_application_on_inspection_created(inspection)
            mirror_inspection(inspection)
            transaction.on_commit(lambda: notify_telegram_inspection_created(request, inspection))
    except IntegrityError:
        inspection = VehicleInspection.objects.get(request_fingerprint=fingerprint)
        return _inspection_created_response(request, inspection, status=200, duplicate=True)

    return _inspection_created_response(request, inspection, status=201)


def _inspection_created_response(request, inspection, status, duplicate=False):
    branch = inspection.branch
    return JsonResponse({
        "ok": True,
        "duplicate": duplicate,
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
        "document_pdf": file_url(request, inspection.document_pdf),
        "branch": {
            "id": branch.id,
            "name": branch.name,
        },
        "admin_url": f"/admin/inspections/vehicleinspection/{inspection.id}/change/",
    }, status=status)


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
