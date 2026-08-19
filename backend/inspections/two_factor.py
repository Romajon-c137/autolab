import re
import secrets
from datetime import timedelta

import requests
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.db.models import F
from django.utils import timezone

from .models import LoginChallenge


class TwoFactorError(Exception):
    pass


def normalize_whatsapp_phone(value):
    digits = re.sub(r"\D+", "", value or "")
    if digits.startswith("00"):
        digits = digits[2:]
    if len(digits) == 9:
        digits = f"996{digits}"
    return digits


def mask_phone(value):
    digits = normalize_whatsapp_phone(value)
    if len(digits) <= 4:
        return "****"
    return f"+{digits[:3]} *** ** {digits[-2:]}"


def create_login_challenge(user):
    code = f"{secrets.randbelow(10000):04d}"
    challenge = LoginChallenge.objects.create(
        user=user,
        code_hash=make_password(code),
        expires_at=timezone.now()
        + timedelta(seconds=settings.TWO_FACTOR_CODE_TTL_SECONDS),
    )
    send_whatsapp_code(user.profile.phone_number, code, challenge)
    return challenge, code if settings.WAZZUP_2FA_DRY_RUN else None


@transaction.atomic
def verify_login_challenge(challenge_id, code):
    challenge = (
        LoginChallenge.objects.select_for_update(of=("self",))
        .select_related("user", "user__profile")
        .filter(challenge_id=challenge_id)
        .first()
    )
    if challenge is None:
        raise TwoFactorError("Код входа не найден.")
    if challenge.is_used:
        raise TwoFactorError("Код уже использован.")
    if challenge.is_expired:
        raise TwoFactorError("Срок действия кода истек.")
    if challenge.attempts >= settings.TWO_FACTOR_MAX_ATTEMPTS:
        raise TwoFactorError("Слишком много попыток. Запросите новый код.")

    normalized_code = re.sub(r"\D+", "", code or "")
    if len(normalized_code) != 4:
        _increment_attempts(challenge)
        raise TwoFactorError("Введите 4-значный код.")

    if not check_password(normalized_code, challenge.code_hash):
        _increment_attempts(challenge)
        raise TwoFactorError("Неверный код.")

    challenge.is_used = True
    challenge.save(update_fields=["is_used"])
    return challenge.user


def send_whatsapp_code(phone_number, code, challenge):
    chat_id = normalize_whatsapp_phone(phone_number)
    if not chat_id:
        raise TwoFactorError("У пользователя не указан телефон WhatsApp.")

    if settings.WAZZUP_2FA_DRY_RUN:
        return

    if not settings.WAZZUP_API_KEY:
        raise TwoFactorError("WAZZUP_API_KEY не настроен на сервере.")
    if not settings.WAZZUP_CHANNEL_ID:
        raise TwoFactorError("WAZZUP_CHANNEL_ID не настроен на сервере.")

    response = requests.post(
        settings.WAZZUP_API_URL,
        headers={
            "Authorization": f"Bearer {settings.WAZZUP_API_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "channelId": settings.WAZZUP_CHANNEL_ID,
            "chatType": "whatsapp",
            "chatId": chat_id,
            "text": f"Код входа Авто лаборатория: {code}",
            "crmMessageId": f"autolab-2fa-{challenge.challenge_id}",
        },
        timeout=15,
    )
    try:
        response_data = response.json()
    except ValueError:
        response_data = {"raw": response.text}

    challenge.wazzup_chat_id = chat_id
    challenge.wazzup_message_id = str(response_data.get("messageId", ""))
    challenge.wazzup_response = response_data
    challenge.save(
        update_fields=["wazzup_chat_id", "wazzup_message_id", "wazzup_response"]
    )

    if response.status_code < 200 or response.status_code >= 300:
        raise TwoFactorError("Сервис отправки кода временно недоступен.")


def _increment_attempts(challenge):
    LoginChallenge.objects.filter(pk=challenge.pk).update(attempts=F("attempts") + 1)
