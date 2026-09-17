from datetime import datetime, timedelta

from django.contrib.auth import get_user_model
from django.contrib.auth import HASH_SESSION_KEY, SESSION_KEY
from django.utils.crypto import constant_time_compare
from django.contrib.sessions.models import Session
from django.http import JsonResponse
from django.utils import timezone

from .models import UserProfile, VehicleInspection


def require_auth(request):
    if request.user.is_authenticated:
        profile = profile_for(request.user)
        request_session_key = request.session.session_key or ""
        is_current_session = (
            not profile.current_session_key
            or profile.current_session_key == request_session_key
        )
        if request.user.is_active and profile.can_use_app and is_current_session:
            return None, request.user
        if not is_current_session:
            return JsonResponse({
                "ok": False,
                "error": "Session was replaced by a newer login",
            }, status=401), None
        return JsonResponse({
            "ok": False,
            "error": "User access is disabled",
        }, status=403), None

    session_key = request.headers.get("X-Session-Key", "").strip()
    if session_key:
        session = Session.objects.filter(
            session_key=session_key,
            expire_date__gt=timezone.now(),
        ).first()
        if session is not None:
            session_data = session.get_decoded()
            user_id = session_data.get(SESSION_KEY)
            user = get_user_model().objects.filter(id=user_id, is_active=True).first()
            session_hash = session_data.get(HASH_SESSION_KEY, "")
            if (
                user is not None
                and session_hash
                and constant_time_compare(session_hash, user.get_session_auth_hash())
            ):
                profile = profile_for(user)
                if not profile.can_use_app:
                    return JsonResponse({
                        "ok": False,
                        "error": "User access is disabled",
                    }, status=403), None
                if profile.current_session_key and profile.current_session_key != session_key:
                    return JsonResponse({
                        "ok": False,
                        "error": "Session was replaced by a newer login",
                    }, status=401), None
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
        UserProfile.ROLE_OPERATOR,
        UserProfile.ROLE_MANAGER,
        UserProfile.ROLE_ADMIN,
    )


def can_view_amounts(user):
    profile = profile_for(user)
    return user.is_superuser or profile.role in (
        UserProfile.ROLE_MANAGER,
        UserProfile.ROLE_ADMIN,
    )


def can_manage_applications(user):
    return profile_for(user).role != UserProfile.ROLE_MVD or user.is_superuser


def can_create_inspections(user):
    return profile_for(user).role != UserProfile.ROLE_MVD or user.is_superuser


def allowed_inspections(user, include_files=True):
    profile = profile_for(user)
    queryset = VehicleInspection.objects.select_related(
        "branch",
        "created_by",
    )
    if include_files:
        queryset = queryset.prefetch_related("extra_photos")

    if user.is_superuser or profile.role in (
        UserProfile.ROLE_ADMIN,
        UserProfile.ROLE_MVD,
    ):
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
