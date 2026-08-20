from django.conf import settings
from django.db import models
from django.utils import timezone
import uuid


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
    phone_number = models.CharField(
        "Телефон WhatsApp",
        max_length=32,
        blank=True,
        help_text="Номер для двухфакторного входа, например +996700123456.",
    )
    can_use_app = models.BooleanField(
        "Доступ к APK",
        default=True,
        help_text="Если выключено, пользователь не сможет войти в web/mobile API.",
    )

    class Meta:
        verbose_name = "Профиль пользователя"
        verbose_name_plural = "Профили пользователей"

    def __str__(self):
        return self.user.get_username()


class LoginChallenge(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="login_challenges",
        verbose_name="Пользователь",
    )
    challenge_id = models.UUIDField(
        "ID проверки",
        default=uuid.uuid4,
        unique=True,
        editable=False,
    )
    code_hash = models.CharField("Хеш кода", max_length=128)
    expires_at = models.DateTimeField("Истекает")
    attempts = models.PositiveSmallIntegerField("Попытки", default=0)
    is_used = models.BooleanField("Использован", default=False)
    wazzup_chat_id = models.CharField("Wazzup chatId", max_length=32, blank=True)
    wazzup_message_id = models.CharField("Wazzup messageId", max_length=64, blank=True)
    wazzup_response = models.JSONField("Ответ Wazzup", null=True, blank=True)
    created_at = models.DateTimeField("Создан", auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Код входа"
        verbose_name_plural = "Коды входа"

    def __str__(self):
        return f"{self.user.get_username()} / {self.challenge_id}"

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at


class ApiRateLimit(models.Model):
    scope = models.CharField(max_length=64)
    identity_hash = models.CharField(max_length=64)
    bucket = models.BigIntegerField()
    count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["scope", "identity_hash", "bucket"],
                name="unique_api_rate_limit_bucket",
            ),
        ]


class OpenAIApiKey(models.Model):
    title = models.CharField("Название", max_length=120, default="Основной ключ")
    api_key = models.CharField("API key", max_length=255)
    model = models.CharField("Модель", max_length=80, default="gpt-5.6-terra")
    is_active = models.BooleanField("Активен", default=True)
    updated_at = models.DateTimeField("Дата обновления", auto_now=True)

    class Meta:
        verbose_name = "OpenAI API key"
        verbose_name_plural = "OpenAI API keys"

    def __str__(self):
        return self.title


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
    amount = models.PositiveIntegerField("Сумма", default=0)
    # Some imported vehicle/body identifiers are not ISO 3779 VINs and can be
    # longer than 17 characters. Keep the source identifier intact.
    vin = models.CharField("VIN / номер кузова", max_length=32)
    request_fingerprint = models.CharField(
        "Fingerprint запроса",
        max_length=64,
        unique=True,
        null=True,
        blank=True,
        editable=False,
    )
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
    application_photo = models.ImageField(
        "Фото заявки",
        upload_to="inspections/application/",
        max_length=255,
        null=True,
        blank=True,
    )
    front_photo = models.ImageField(
        "Фото спереди",
        upload_to="inspections/front/",
        max_length=255,
        null=True,
        blank=True,
    )
    rear_photo = models.ImageField(
        "Фото сзади",
        upload_to="inspections/rear/",
        max_length=255,
        null=True,
        blank=True,
    )
    left_photo = models.ImageField(
        "Фото слева",
        upload_to="inspections/left/",
        max_length=255,
        null=True,
        blank=True,
    )
    right_photo = models.ImageField(
        "Фото справа",
        upload_to="inspections/right/",
        max_length=255,
        null=True,
        blank=True,
    )
    mileage_photo = models.ImageField(
        "Фото пробега",
        upload_to="inspections/mileage/",
        max_length=255,
        null=True,
        blank=True,
    )
    vin_photo = models.ImageField(
        "Фото VIN",
        upload_to="inspections/vin/",
        max_length=255,
        null=True,
        blank=True,
    )
    document_pdf = models.FileField(
        "Документ PDF",
        upload_to="inspections/documents/",
        max_length=255,
        null=True,
        blank=True,
    )
    application_pdf = models.FileField(
        "PDF заявки клиента",
        upload_to="inspections/applications/",
        max_length=255,
        null=True,
        blank=True,
    )
    front_photo_taken_at = models.DateTimeField("Дата фото спереди", null=True, blank=True)
    rear_photo_taken_at = models.DateTimeField("Дата фото сзади", null=True, blank=True)
    left_photo_taken_at = models.DateTimeField("Дата фото слева", null=True, blank=True)
    right_photo_taken_at = models.DateTimeField("Дата фото справа", null=True, blank=True)
    mileage_photo_taken_at = models.DateTimeField("Дата фото пробега", null=True, blank=True)
    vin_photo_taken_at = models.DateTimeField("Дата фото VIN", null=True, blank=True)
    application_photo_taken_at = models.DateTimeField("Дата фото заявки", null=True, blank=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Осмотр авто"
        verbose_name_plural = "Осмотры авто"

    def __str__(self):
        return f"{self.title} ({self.vin})"


class InspectionPrice(models.Model):
    operation_type = models.CharField(
        "Тип операции",
        max_length=32,
        choices=VehicleInspection.OPERATION_CHOICES,
    )
    vehicle_category = models.CharField(
        "Категория авто",
        max_length=2,
        choices=VehicleInspection.CATEGORY_CHOICES,
        blank=True,
        help_text="Заполняется для СБКТС и техосмотра. Для остальных операций оставить пустым.",
    )
    amount = models.PositiveIntegerField("Сумма")
    effective_from = models.DateField("Действует с")
    is_active = models.BooleanField("Активна", default=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["operation_type", "vehicle_category", "-effective_from"]
        constraints = [
            models.UniqueConstraint(
                fields=["operation_type", "vehicle_category", "effective_from"],
                name="unique_inspection_price_period",
            ),
        ]
        verbose_name = "Цена осмотра"
        verbose_name_plural = "Цены осмотров"

    def __str__(self):
        category = f" {self.vehicle_category}" if self.vehicle_category else ""
        return f"{self.get_operation_type_display()}{category}: {self.amount}"


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
        max_length=255,
    )
    taken_at = models.DateTimeField("Дата фото", null=True, blank=True)
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["id"]
        verbose_name = "Дополнительное фото"
        verbose_name_plural = "Дополнительные фото"

    def __str__(self):
        return f"Фото #{self.id} осмотра #{self.inspection_id}"


class ClientApplication(models.Model):
    applicant_name = models.CharField("ФИО заявителя", max_length=200, blank=True)
    inn = models.CharField("ИНН", max_length=20, blank=True)
    phone = models.CharField("Телефон", max_length=32, blank=True)
    vehicle_name = models.CharField("Марка / модель авто", max_length=120, blank=True)
    plate_number = models.CharField("Гос номер", max_length=20, blank=True)
    year = models.CharField("Год выпуска", max_length=10, blank=True)
    vin = models.CharField("VIN / номер кузова", max_length=32)
    pdf = models.FileField(
        "PDF заявки",
        upload_to="inspections/applications/",
        max_length=255,
    )
    signature = models.ImageField(
        "Подпись заявителя",
        upload_to="inspections/application_signatures/",
        max_length=255,
        null=True,
        blank=True,
    )
    inspection = models.ForeignKey(
        VehicleInspection,
        on_delete=models.SET_NULL,
        related_name="client_applications",
        null=True,
        blank=True,
        verbose_name="Осмотр",
    )
    created_at = models.DateTimeField("Дата создания", auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Заявка клиента"
        verbose_name_plural = "Заявки клиентов"

    def __str__(self):
        return f"{self.applicant_name or 'Без имени'} ({self.vin})"
