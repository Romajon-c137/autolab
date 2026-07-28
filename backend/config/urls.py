"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from pathlib import Path

from django.contrib import admin
from django.conf import settings
from django.conf.urls.static import static
from django.core.files.storage import FileSystemStorage
from django.http import JsonResponse
from django.urls import path
from django.views.decorators.csrf import csrf_exempt
from inspections.views import (
    branches_view,
    create_inspection,
    daily_reports_collection,
    inspection_detail,
    inspections_collection,
    login_view,
    logout_view,
    me_view,
    reports_summary,
)

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}


def ping(request):
    return JsonResponse({
        "ok": True,
        "message": "Django server is reachable",
    })


@csrf_exempt
def upload_image(request):
    if request.method != "POST":
        return JsonResponse({
            "ok": False,
            "error": "Only POST is allowed",
        }, status=405)

    image = request.FILES.get("image")
    if image is None:
        return JsonResponse({
            "ok": False,
            "error": "Field 'image' is required",
        }, status=400)

    image_suffix = Path(image.name).suffix.lower()
    is_image_content_type = image.content_type.startswith("image/")
    is_image_extension = image_suffix in IMAGE_EXTENSIONS

    if not is_image_content_type and not is_image_extension:
        return JsonResponse({
            "ok": False,
            "error": "Uploaded file must be an image",
            "content_type": image.content_type,
            "filename": image.name,
        }, status=400)

    storage = FileSystemStorage(location=settings.MEDIA_ROOT)
    filename = storage.save(image.name, image)
    saved_url = settings.MEDIA_URL + Path(filename).as_posix()

    return JsonResponse({
        "ok": True,
        "filename": filename,
        "size": image.size,
        "content_type": image.content_type,
        "url": saved_url,
    })


urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/ping/', ping, name='ping'),
    path('api/auth/login/', login_view, name='api-login'),
    path('api/auth/logout/', logout_view, name='api-logout'),
    path('api/auth/me/', me_view, name='api-me'),
    path('api/branches/', branches_view, name='branches'),
    path('api/inspections/', inspections_collection, name='inspections-collection'),
    path('api/inspections/<int:inspection_id>/', inspection_detail, name='inspection-detail'),
    path('api/reports/summary/', reports_summary, name='reports-summary'),
    path('api/daily-reports/', daily_reports_collection, name='daily-reports'),
    path('api/upload-image/', upload_image, name='upload-image'),
    path('api/inspections/create/', create_inspection, name='create-inspection'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
