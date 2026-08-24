import io
import tempfile
from datetime import timedelta
from pathlib import Path

from PIL import Image
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from .models import Branch, LoginChallenge, UserProfile, VehicleInspection
from .two_factor import TwoFactorError, verify_login_challenge


def image_bytes():
    output = io.BytesIO()
    Image.new("RGB", (2, 2), "white").save(output, "PNG")
    return output.getvalue()


def uploaded_image(name="photo.png"):
    return SimpleUploadedFile(name, image_bytes(), content_type="image/png")


def uploaded_pdf(name="document.pdf"):
    return SimpleUploadedFile(name, b"%PDF-1.4\n%%EOF\n", content_type="application/pdf")


@override_settings(
    CLIENT_APPLICATION_API_KEY="client-secret",
    MAX_IMAGE_UPLOAD_BYTES=1024 * 1024,
    MAX_PDF_UPLOAD_BYTES=1024 * 1024,
    SECURE_SSL_REDIRECT=False,
)
class SecurityTests(TestCase):
    def setUp(self):
        cache.clear()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.override = override_settings(
            MEDIA_ROOT=Path(self.temp_dir.name),
            AUTOLAB_STORAGE_ROOT=Path(self.temp_dir.name),
        )
        self.override.enable()
        self.branch = Branch.objects.create(name="Test branch")
        self.user = get_user_model().objects.create_user("operator", password="A-safe-password-123")
        profile = self.user.profile
        profile.branch = self.branch
        profile.role = UserProfile.ROLE_OPERATOR
        profile.save()

    def tearDown(self):
        self.override.disable()
        self.temp_dir.cleanup()

    def test_upload_endpoint_requires_authentication(self):
        response = self.client.post("/api/upload-image/", {"image": uploaded_image()})
        self.assertEqual(response.status_code, 401)

    def test_upload_rejects_spoofed_image(self):
        self.client.force_login(self.user)
        fake = SimpleUploadedFile("fake.jpg", b"not an image", content_type="image/jpeg")
        response = self.client.post("/api/upload-image/", {"image": fake})
        self.assertEqual(response.status_code, 400)

    def test_client_application_requires_service_key(self):
        response = self.client.post(
            "/api/client-applications/",
            {"vin": "KNAG6412BLA015238", "application_pdf": uploaded_pdf()},
        )
        self.assertEqual(response.status_code, 401)

    def test_client_application_cannot_replace_existing_pdf(self):
        inspection = VehicleInspection.objects.create(
            title="Car", brand="Car", vin="KNAG6412BLA015238",
            branch=self.branch, created_by=self.user,
            application_pdf=uploaded_pdf("existing.pdf"),
        )
        response = self.client.post(
            "/api/client-applications/",
            {"vin": inspection.vin, "application_pdf": uploaded_pdf("replacement.pdf")},
            HTTP_X_CLIENT_APPLICATION_KEY="client-secret",
        )
        self.assertEqual(response.status_code, 409)

    def test_identical_inspection_request_is_idempotent(self):
        self.client.force_login(self.user)
        data = {
            "title": "Honda Fit", "brand": "Honda Fit",
            "vin": "JHMGD17507S202261", "operation_type": "tech_inspection",
            "vehicle_category": "M1", "front_photo": uploaded_image(),
        }
        first = self.client.post("/api/inspections/", data)
        self.assertEqual(first.status_code, 201, first.content)
        data["front_photo"] = uploaded_image()
        second = self.client.post("/api/inspections/", data)
        self.assertEqual(second.status_code, 200, second.content)
        self.assertTrue(second.json()["duplicate"])
        self.assertEqual(first.json()["id"], second.json()["id"])
        self.assertEqual(VehicleInspection.objects.count(), 1)

    def test_invalid_vehicle_identifier_is_rejected(self):
        self.client.force_login(self.user)
        response = self.client.post("/api/inspections/", {"brand": "Car", "vin": "bad vin!"})
        self.assertEqual(response.status_code, 400)


class TwoFactorTests(TestCase):
    def test_used_challenge_cannot_be_reused(self):
        user = get_user_model().objects.create_user("twofactor", password="A-safe-password-123")
        challenge = LoginChallenge.objects.create(
            user=user, code_hash="unused",
            expires_at=timezone.now() + timedelta(minutes=5), is_used=True,
        )
        with self.assertRaises(TwoFactorError):
            verify_login_challenge(str(challenge.challenge_id), "1234")


@override_settings(SECURE_SSL_REDIRECT=False)
class PhotoPreviewTests(TestCase):
    def test_preview_is_full_hd_sized_webp_and_keeps_original(self):
        with tempfile.TemporaryDirectory() as media_root:
            source = Path(media_root) / "inspections" / "front" / "large.jpg"
            source.parent.mkdir(parents=True)
            Image.new("RGB", (3000, 2000), "white").save(source, "JPEG", quality=95)
            original_size = source.stat().st_size

            with override_settings(MEDIA_ROOT=media_root):
                response = self.client.get("/api/photo-preview/inspections/front/large.jpg")
                preview_bytes = b"".join(response.streaming_content)

            self.assertEqual(response.status_code, 200)
            self.assertEqual(response["Content-Type"], "image/webp")
            with Image.open(io.BytesIO(preview_bytes)) as preview:
                self.assertEqual(preview.format, "WEBP")
                self.assertLessEqual(max(preview.size), 1920)
            self.assertEqual(source.stat().st_size, original_size)


@override_settings(SECURE_SSL_REDIRECT=False)
class RolePermissionTests(TestCase):
    def setUp(self):
        self.branch = Branch.objects.create(name="Role test branch")
        self.other_branch = Branch.objects.create(name="Other branch")
        self.user = get_user_model().objects.create_user(
            "role-user",
            password="A-safe-password-123",
        )
        self.user.profile.branch = self.branch
        self.user.profile.save(update_fields=["branch"])
        self.inspection = VehicleInspection.objects.create(
            title="Test car",
            brand="Test car",
            vin="XMB4A11CDAA290161",
            amount=1000,
            branch=self.other_branch,
        )
        self.client.force_login(self.user)

    def set_role(self, role):
        self.user.profile.role = role
        self.user.profile.save(update_fields=["role"])

    def test_mvd_has_global_read_only_registry_without_sensitive_fields(self):
        self.set_role(UserProfile.ROLE_MVD)

        response = self.client.get("/api/inspections/", {"vin": self.inspection.vin})

        self.assertEqual(response.status_code, 200)
        item = response.json()["inspections"][0]
        self.assertEqual(item["id"], self.inspection.id)
        self.assertNotIn("amount", item)
        self.assertNotIn("application_pdf", item)
        self.assertEqual(self.client.get("/api/reports/summary/").status_code, 403)
        self.assertEqual(self.client.get("/api/client-applications/list/").status_code, 403)
        self.assertEqual(self.client.post("/api/inspections/", {}).status_code, 403)

    def test_operator_can_see_count_reports_and_manage_applications_without_amounts(self):
        self.set_role(UserProfile.ROLE_OPERATOR)
        own_inspection = VehicleInspection.objects.create(
            title="Own car",
            brand="Own car",
            vin="KNAG6412BLA015238",
            amount=850,
            branch=self.branch,
            created_by=self.user,
        )

        list_response = self.client.get("/api/inspections/", {"vin": own_inspection.vin})

        self.assertEqual(list_response.status_code, 200)
        self.assertNotIn("amount", list_response.json()["inspections"][0])
        self.assertEqual(self.client.get("/api/reports/summary/").status_code, 200)
        self.assertEqual(self.client.get("/api/client-applications/list/").status_code, 200)


@override_settings(SECURE_SSL_REDIRECT=False)
class AdminPasswordTests(TestCase):
    def test_password_generation_rejects_get(self):
        admin = get_user_model().objects.create_superuser(
            "admin", "admin@example.com", "A-safe-password-123"
        )
        target = get_user_model().objects.create_user("target", password="A-safe-password-123")
        self.client.force_login(admin)
        url = reverse("admin:auth_user_generate_password", args=[target.pk])
        self.assertEqual(self.client.get(url).status_code, 405)
