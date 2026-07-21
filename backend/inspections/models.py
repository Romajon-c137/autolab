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


class AiApiKey(models.Model):
    name = models.CharField("Название", max_length=120, default="OpenAI")
    api_key = models.CharField("API key", max_length=255)
    model = models.CharField("Модель", max_length=80, default="gpt-5.6")
    is_active = models.BooleanField("Активен", default=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)
    updated_at = models.DateTimeField("Дата обновления", auto_now=True)

    class Meta:
        ordering = ["-is_active", "-updated_at"]
        verbose_name = "AI API key"
        verbose_name_plural = "AI API keys"

    def __str__(self):
        return self.name

    @property
    def masked_key(self):
        if len(self.api_key) <= 10:
            return "*****"

        return f"{self.api_key[:6]}...{self.api_key[-4:]}"


class VehicleInspection(models.Model):
    title = models.CharField("Название", max_length=120, blank=True)
    plate_number = models.CharField("Гос номер", max_length=20, blank=True)
    brand = models.CharField("Марка авто", max_length=80, blank=True)
    country = models.CharField("Страна", max_length=80, blank=True)
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
