from django.http import HttpResponse
from django.conf import settings


class DevCorsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.method == "OPTIONS":
            response = HttpResponse()
        else:
            response = self.get_response(request)

        origin = request.headers.get("Origin", "")
        allowed_origins = getattr(settings, "CORS_ALLOWED_ORIGINS", [])
        origin_is_allowed = settings.DEBUG or origin in allowed_origins

        if origin and origin_is_allowed:
            response["Access-Control-Allow-Origin"] = origin
            response["Access-Control-Allow-Credentials"] = "true"
            response["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
            response["Access-Control-Allow-Headers"] = (
                "Content-Type, Cookie, X-Requested-With, X-Session-Key"
            )

        return response
