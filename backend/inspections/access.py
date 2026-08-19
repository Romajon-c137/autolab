from datetime import datetime, timedelta

from django.contrib.auth import get_user_model
from django.contrib.sessions.models import Session
from django.http import JsonResponse
from django.utils import timezone

from .models import UserProfile, VehicleInspection


def require_auth(request):
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


def profile_for(user):
    profile, _created = UserProfile.objects.get_or_create(user=user)
    return profile


def is_report_user(user):
    profile = profile_for(user)
    return user.is_superuser or profile.role in (
        UserProfile.ROLE_MANAGER,
        UserProfile.ROLE_ADMIN,
    )


def allowed_inspections(user):
    profile = profile_for(user)
    queryset = VehicleInspection.objects.select_related(
        "branch",
        "created_by",
    ).prefetch_related("extra_photos")

    if user.is_superuser or profile.role == UserProfile.ROLE_ADMIN:
        return queryset

    if profile.branch_id is None:
        return queryset.none()

    return queryset.filter(branch_id=profile.branch_id)


def date_range(request):
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
