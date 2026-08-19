import html
import os

import requests
from django.utils import timezone

from .serializers import file_url


def notify_telegram_inspection_created(request, inspection):
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
    document_url = file_url(request, inspection.document_pdf)

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
