from django.conf import settings
from django.db import models


class Branch(models.Model):
    name = models.CharField("Название филиала", max_length=120, unique=True)
    is_active = models.BooleanField("Активен", default=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["name"]
        verbose_name = "Филиал"
        verbose_name_plural = "Филиалы"

    def __str__(self):
        return self.name


class UserProfile(models.Model):
    ROLE_OPERATOR = "operator"
    ROLE_MANAGER = "manager"
    ROLE_ADMIN = "admin"
    ROLE_CHOICES = (
        (ROLE_OPERATOR, "Оператор"),
        (ROLE_MANAGER, "Руководитель"),
        (ROLE_ADMIN, "Администратор"),
    )

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile",
        verbose_name="Пользователь",
    )
    branch = models.ForeignKey(
        Branch,
        on_delete=models.PROTECT,
        related_name="users",
        null=True,
        blank=True,
        verbose_name="Филиал",
    )
    current_session_key = models.CharField(
        "Текущая сессия",
        max_length=40,
        blank=True,
    )
    role = models.CharField(
        "Роль",
        max_length=20,
        choices=ROLE_CHOICES,
        default=ROLE_OPERATOR,
    )

    class Meta:
        verbose_name = "Профиль пользователя"
        verbose_name_plural = "Профили пользователей"

    def __str__(self):
        return self.user.get_username()


class VehicleInspection(models.Model):
    OPERATION_TECH_INSPECTION = "tech_inspection"
    OPERATION_SBGTS = "sbgts"
    OPERATION_LEGALIZATION = "legalization"
    OPERATION_CONVERSION = "conversion"
    OPERATION_CHOICES = (
        (OPERATION_TECH_INSPECTION, "Техосмотр"),
        (OPERATION_SBGTS, "СБКТС"),
        (OPERATION_LEGALIZATION, "Легализация"),
        (OPERATION_CONVERSION, "Переоборудование"),
    )

    CATEGORY_M1 = "M1"
    CATEGORY_M2 = "M2"
    CATEGORY_M3 = "M3"
    CATEGORY_N1 = "N1"
    CATEGORY_N2 = "N2"
    CATEGORY_N3 = "N3"
    CATEGORY_CHOICES = (
        (CATEGORY_M1, "M1"),
        (CATEGORY_M2, "M2"),
        (CATEGORY_M3, "M3"),
        (CATEGORY_N1, "N1"),
        (CATEGORY_N2, "N2"),
        (CATEGORY_N3, "N3"),
    )

    title = models.CharField("Название", max_length=120, blank=True)
    operation_type = models.CharField(
        "Категория операции",
        max_length=32,
        choices=OPERATION_CHOICES,
        default=OPERATION_SBGTS,
    )
    plate_number = models.CharField("Гос номер", max_length=20, blank=True)
    brand = models.CharField("Марка авто", max_length=80, blank=True)
    country = models.CharField("Страна", max_length=80, blank=True)
    vehicle_category = models.CharField(
        "Категория авто",
        max_length=2,
        choices=CATEGORY_CHOICES,
        default=CATEGORY_M1,
    )
    mileage = models.PositiveIntegerField("Пробег", null=True, blank=True)
    vin = models.CharField("VIN номер", max_length=17, blank=True)
    branch = models.ForeignKey(
        Branch,
        on_delete=models.PROTECT,
        related_name="inspections",
        null=True,
        blank=True,
        verbose_name="Филиал",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="inspections",
        null=True,
        blank=True,
        verbose_name="Создал",
    )
    front_photo = models.ImageField(
        "Фото спереди",
        upload_to="inspections/front/",
        null=True,
        blank=True,
    )
    rear_photo = models.ImageField(
        "Фото сзади",
        upload_to="inspections/rear/",
        null=True,
        blank=True,
    )
    left_photo = models.ImageField(
        "Фото слева",
        upload_to="inspections/left/",
        null=True,
        blank=True,
    )
    right_photo = models.ImageField(
        "Фото справа",
        upload_to="inspections/right/",
        null=True,
        blank=True,
    )
    mileage_photo = models.ImageField(
        "Фото пробега",
        upload_to="inspections/mileage/",
        null=True,
        blank=True,
    )
    vin_photo = models.ImageField(
        "Фото VIN",
        upload_to="inspections/vin/",
        null=True,
        blank=True,
    )
    document_pdf = models.FileField(
        "Документ PDF",
        upload_to="inspections/documents/",
        null=True,
        blank=True,
    )
    front_photo_taken_at = models.DateTimeField("Дата фото спереди", null=True, blank=True)
    rear_photo_taken_at = models.DateTimeField("Дата фото сзади", null=True, blank=True)
    left_photo_taken_at = models.DateTimeField("Дата фото слева", null=True, blank=True)
    right_photo_taken_at = models.DateTimeField("Дата фото справа", null=True, blank=True)
    mileage_photo_taken_at = models.DateTimeField("Дата фото пробега", null=True, blank=True)
    vin_photo_taken_at = models.DateTimeField("Дата фото VIN", null=True, blank=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Осмотр авто"
        verbose_name_plural = "Осмотры авто"

    def __str__(self):
        return f"{self.title} ({self.vin})"


class VehicleInspectionExtraPhoto(models.Model):
    inspection = models.ForeignKey(
        VehicleInspection,
        on_delete=models.CASCADE,
        related_name="extra_photos",
        verbose_name="Осмотр",
    )
    image = models.ImageField(
        "Фото переоборудованной части",
        upload_to="inspections/conversion/",
    )
    taken_at = models.DateTimeField("Дата фото", null=True, blank=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["id"]
        verbose_name = "Дополнительное фото"
        verbose_name_plural = "Дополнительные фото"

    def __str__(self):
        return f"Фото #{self.id} осмотра #{self.inspection_id}"


class DailyInspectionReport(models.Model):
    report_date = models.DateField("Дата отчета")
    branch = models.ForeignKey(
        Branch,
        on_delete=models.PROTECT,
        related_name="daily_reports",
        null=True,
        blank=True,
        verbose_name="Филиал",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="daily_inspection_reports",
        null=True,
        blank=True,
        verbose_name="Создал",
    )
    rows = models.JSONField("Строки отчета", default=list, blank=True)
    total_count = models.PositiveIntegerField("Всего", default=0)
    category_counts = models.JSONField("Итоги по категориям", default=dict, blank=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)
    updated_at = models.DateTimeField("Дата обновления", auto_now=True)

    class Meta:
        ordering = ["-report_date", "branch__name"]
        constraints = [
            models.UniqueConstraint(
                fields=["report_date", "branch"],
                name="unique_daily_inspection_report_per_branch",
            ),
        ]
        verbose_name = "Дневной отчет осмотров"
        verbose_name_plural = "Дневные отчеты осмотров"

    def __str__(self):
        branch_name = self.branch.name if self.branch else "Без филиала"
        return f"{self.report_date} - {branch_name}"
