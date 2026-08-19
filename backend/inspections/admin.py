from django.contrib import admin
from django import forms
from django.contrib.auth.admin import UserAdmin
from django.contrib.auth.models import User
from django.core.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404, redirect
from django.urls import path
from django.utils.crypto import get_random_string
from django.utils.html import format_html
from django.utils.decorators import method_decorator
from django.views.decorators.http import require_POST

from .models import (
    Branch,
    InspectionPrice,
    LoginChallenge,
    OpenAIApiKey,
    UserProfile,
    VehicleInspection,
    VehicleInspectionExtraPhoto,
)


class UserProfileInline(admin.StackedInline):
    model = UserProfile
    can_delete = False
    extra = 0
    fields = ("branch", "role", "phone_number", "can_use_app", "current_session_key")
    readonly_fields = ("current_session_key",)


admin.site.unregister(User)


@admin.register(User)
class UserWithProfileAdmin(UserAdmin):
    inlines = (UserProfileInline,)
    change_form_template = "admin/auth/user/change_form.html"

    def get_inline_instances(self, request, obj=None):
        if obj is None:
            return []

        UserProfile.objects.get_or_create(user=obj)
        return super().get_inline_instances(request, obj)

    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path(
                "<path:object_id>/generate-password/",
                self.admin_site.admin_view(self.generate_password_view),
                name="auth_user_generate_password",
            ),
        ]
        return custom_urls + urls

    @method_decorator(require_POST)
    def generate_password_view(self, request, object_id):
        if not self.has_change_permission(request):
            raise PermissionDenied

        user = get_object_or_404(User, pk=object_id)
        alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789"
        password = get_random_string(10, allowed_chars=alphabet)
        user.set_password(password)
        user.save(update_fields=["password"])

        self.message_user(
            request,
            f"Новый пароль для пользователя {user.get_username()}: {password}",
        )
        return redirect("admin:auth_user_change", object_id)


@admin.register(Branch)
class BranchAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("name",)


class OpenAIApiKeyAdminForm(forms.ModelForm):
    class Meta:
        model = OpenAIApiKey
        fields = "__all__"
        widgets = {"api_key": forms.PasswordInput(render_value=False)}

    def clean_api_key(self):
        value = self.cleaned_data.get("api_key", "").strip()
        if value:
            return value
        if self.instance.pk:
            return OpenAIApiKey.objects.only("api_key").get(pk=self.instance.pk).api_key
        raise forms.ValidationError("API key is required")


@admin.register(OpenAIApiKey)
class OpenAIApiKeyAdmin(admin.ModelAdmin):
    form = OpenAIApiKeyAdminForm
    list_display = ("title", "model", "is_active", "updated_at")
    list_filter = ("is_active", "model")
    search_fields = ("title", "model")
    fields = ("title", "api_key", "model", "is_active", "updated_at")
    readonly_fields = ("updated_at",)


@admin.register(LoginChallenge)
class LoginChallengeAdmin(admin.ModelAdmin):
    list_display = (
        "created_at",
        "user",
        "wazzup_chat_id",
        "wazzup_message_id",
        "expires_at",
        "attempts",
        "is_used",
    )
    list_filter = ("is_used", "created_at")
    search_fields = (
        "user__username",
        "wazzup_chat_id",
        "wazzup_message_id",
        "challenge_id",
    )
    readonly_fields = (
        "user",
        "challenge_id",
        "code_hash",
        "expires_at",
        "attempts",
        "is_used",
        "wazzup_chat_id",
        "wazzup_message_id",
        "wazzup_response",
        "created_at",
    )


@admin.register(InspectionPrice)
class InspectionPriceAdmin(admin.ModelAdmin):
    list_display = (
        "operation_type",
        "vehicle_category",
        "amount",
        "effective_from",
        "is_active",
        "created_at",
    )
    list_filter = ("operation_type", "vehicle_category", "is_active", "effective_from")
    search_fields = ("operation_type", "vehicle_category")
    fields = (
        "operation_type",
        "vehicle_category",
        "amount",
        "effective_from",
        "is_active",
        "created_at",
    )
    readonly_fields = ("created_at",)


class VehicleInspectionExtraPhotoInline(admin.TabularInline):
    model = VehicleInspectionExtraPhoto
    extra = 0
    readonly_fields = ("created_at", "preview")
    fields = ("image", "preview", "taken_at", "created_at")

    @admin.display(description="Превью")
    def preview(self, obj):
        if not obj.image:
            return "-"
        return format_html(
            '<a href="{}" target="_blank"><img src="{}" style="max-height:120px;max-width:180px;object-fit:cover;border-radius:6px;" /></a>',
            obj.image.url,
            obj.image.url,
        )


@admin.register(VehicleInspection)
class VehicleInspectionAdmin(admin.ModelAdmin):
    inlines = (VehicleInspectionExtraPhotoInline,)
    list_display = (
        "id",
        "title",
        "operation_type",
        "plate_number",
        "brand",
        "country",
        "vehicle_category",
        "amount",
        "branch",
        "created_by",
        "created_at",
        "mileage_preview",
        "vin_preview",
        "front_preview",
        "rear_preview",
        "left_preview",
        "right_preview",
        "document_link",
        "application_link",
    )
    readonly_fields = (
        "created_at",
        "amount",
        "mileage_preview",
        "vin_preview",
        "front_preview",
        "rear_preview",
        "left_preview",
        "right_preview",
        "document_link",
        "application_link",
    )
    search_fields = ("title", "plate_number", "brand", "country", "vin")
    list_filter = (
        "operation_type",
        "vehicle_category",
        "branch",
        "created_by",
        "created_at",
    )

    fieldsets = (
        ("Данные авто", {
            "fields": (
                "operation_type",
                "plate_number",
                "brand",
                "country",
                "vehicle_category",
                "amount",
                "vin",
            ),
        }),
        ("Данные осмотра", {
            "fields": (
                "title",
                "branch",
                "created_by",
                "created_at",
            ),
        }),
        ("Фотографии", {
            "fields": (
                ("mileage_photo", "mileage_preview"),
                ("vin_photo", "vin_preview"),
                ("front_photo", "front_preview"),
                ("rear_photo", "rear_preview"),
                ("left_photo", "left_preview"),
                ("right_photo", "right_preview"),
            ),
        }),
        ("Документ", {
            "fields": (
                "document_pdf",
                "document_link",
                "application_pdf",
                "application_link",
            ),
        }),
    )

    @admin.display(description="Пробег")
    def mileage_preview(self, obj):
        return self._image_preview(obj.mileage_photo)

    @admin.display(description="VIN")
    def vin_preview(self, obj):
        return self._image_preview(obj.vin_photo)

    @admin.display(description="Спереди")
    def front_preview(self, obj):
        return self._image_preview(obj.front_photo)

    @admin.display(description="Сзади")
    def rear_preview(self, obj):
        return self._image_preview(obj.rear_photo)

    @admin.display(description="Слева")
    def left_preview(self, obj):
        return self._image_preview(obj.left_photo)

    @admin.display(description="Справа")
    def right_preview(self, obj):
        return self._image_preview(obj.right_photo)

    @admin.display(description="PDF документ")
    def document_link(self, obj):
        if not obj.document_pdf:
            return "-"

        return format_html(
            '<a href="{url}" target="_blank">Открыть PDF</a>',
            url=obj.document_pdf.url,
        )

    @admin.display(description="PDF заявки")
    def application_link(self, obj):
        if not obj.application_pdf:
            return "-"

        return format_html(
            '<a href="{url}" target="_blank">Открыть заявку</a>',
            url=obj.application_pdf.url,
        )

    def _image_preview(self, image):
        if not image:
            return "-"

        return format_html(
            '<a href="{url}" target="_blank">'
            '<img src="{url}" style="height:80px; width:110px; object-fit:cover;" />'
            '</a>',
            url=image.url,
        )
