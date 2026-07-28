from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.contrib.auth.models import User
from django.core.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404, redirect
from django.urls import path
from django.utils.crypto import get_random_string
from django.utils.html import format_html

from .models import Branch, DailyInspectionReport, UserProfile, VehicleInspection


class UserProfileInline(admin.StackedInline):
    model = UserProfile
    can_delete = False
    extra = 0
    fields = ("branch", "role", "current_session_key")
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


@admin.register(VehicleInspection)
class VehicleInspectionAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "title",
        "plate_number",
        "brand",
        "country",
        "vehicle_category",
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
    )
    readonly_fields = (
        "created_at",
        "mileage_preview",
        "vin_preview",
        "front_preview",
        "rear_preview",
        "left_preview",
        "right_preview",
        "document_link",
    )
    search_fields = ("title", "plate_number", "brand", "country", "vin")
    list_filter = ("vehicle_category", "branch", "created_by", "created_at")

    fieldsets = (
        ("Данные авто", {
            "fields": (
                "plate_number",
                "brand",
                "country",
                "vehicle_category",
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

    def _image_preview(self, image):
        if not image:
            return "-"

        return format_html(
            '<a href="{url}" target="_blank">'
            '<img src="{url}" style="height:80px; width:110px; object-fit:cover;" />'
            '</a>',
            url=image.url,
        )


@admin.register(DailyInspectionReport)
class DailyInspectionReportAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "report_date",
        "branch",
        "total_count",
        "category_counts_display",
        "created_by",
        "updated_at",
    )
    list_filter = ("report_date", "branch", "created_by")
    search_fields = ("branch__name", "created_by__username")
    readonly_fields = ("created_at", "updated_at", "category_counts_display")
    fields = (
        "report_date",
        "branch",
        "created_by",
        "total_count",
        "category_counts_display",
        "rows",
        "category_counts",
        "created_at",
        "updated_at",
    )

    @admin.display(description="Категории")
    def category_counts_display(self, obj):
        if not obj.category_counts:
            return "-"

        return ", ".join(
            f"{category}: {count}"
            for category, count in sorted(obj.category_counts.items())
        )
