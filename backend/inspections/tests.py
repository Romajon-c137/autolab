import io
import tempfile
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

from PIL import Image
from django.contrib.auth import get_user_model
from django.contrib.sessions.models import Session
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from .application_pdfs import detach_application, save_client_application
from .background_tasks import process_next_postprocessing_job, schedule_inspection_postprocessing
from .models import (
    Branch, ClientApplication, InspectionPostprocessJob, InspectionPrice,
    LoginChallenge, UserProfile, VehicleInspection,
)
from .storage_mirror import mirror_inspection
from .two_factor import TwoFactorError, verify_login_challenge
from .views import normalize_vehicle_category


def image_bytes():
    output = io.BytesIO()
    Image.new("RGB", (2, 2), "white").save(output, "PNG")
    return output.getvalue()


def uploaded_image(name="photo.png"):
    return SimpleUploadedFile(name, image_bytes(), content_type="image/png")


def uploaded_pdf(name="document.pdf"):
    return SimpleUploadedFile(name, b"%PDF-1.4\n%%EOF\n", content_type="application/pdf")


class VehicleCategoryNormalizationTests(TestCase):
    def test_accepts_current_and_legacy_mobile_values(self):
        self.assertEqual(normalize_vehicle_category("n2"), "N2")
        self.assertEqual(normalize_vehicle_category("_VehicleCategory.n2"), "N2")
        self.assertEqual(normalize_vehicle_category("Категория Н1"), "N1")

    def test_does_not_guess_unknown_category(self):
        self.assertEqual(normalize_vehicle_category("03-4"), "")


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
        InspectionPrice.objects.create(
            operation_type=VehicleInspection.OPERATION_TECH_INSPECTION,
            vehicle_category=VehicleInspection.CATEGORY_M1,
            amount=850,
            effective_from=timezone.localdate(),
        )

    def tearDown(self):
        self.override.disable()
        self.temp_dir.cleanup()

    def test_upload_endpoint_requires_authentication(self):
        response = self.client.post("/api/upload-image/", {"image": uploaded_image()})
        self.assertEqual(response.status_code, 401)

    def test_expired_header_session_is_rejected(self):
        self.client.force_login(self.user)
        session_key = self.client.session.session_key
        Session.objects.filter(session_key=session_key).update(
            expire_date=timezone.now() - timedelta(seconds=1)
        )
        response = Client().get("/api/auth/me/", HTTP_X_SESSION_KEY=session_key)
        self.assertEqual(response.status_code, 401)

    def test_password_change_invalidates_header_session(self):
        self.client.force_login(self.user)
        session_key = self.client.session.session_key
        self.user.set_password("A-new-safe-password-456")
        self.user.save(update_fields=["password"])
        response = Client().get("/api/auth/me/", HTTP_X_SESSION_KEY=session_key)
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
            {
                "vin": inspection.vin,
                "application_pdf": uploaded_pdf("replacement.pdf"),
                "signature": uploaded_image("signature.png"),
            },
            HTTP_X_CLIENT_APPLICATION_KEY="client-secret",
        )
        self.assertEqual(response.status_code, 409)

    def test_client_application_request_is_idempotent(self):
        payload = {
            "vin": "KNAG6412BLA015238",
            "request_id": "application-request-123",
            "application_pdf": uploaded_pdf(),
            "signature": uploaded_image("signature.png"),
        }
        first = self.client.post(
            "/api/client-applications/", payload,
            HTTP_X_CLIENT_APPLICATION_KEY="client-secret",
        )
        second = self.client.post(
            "/api/client-applications/",
            {"vin": payload["vin"], "request_id": payload["request_id"]},
            HTTP_X_CLIENT_APPLICATION_KEY="client-secret",
        )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertTrue(second.json()["duplicate"])
        self.assertEqual(ClientApplication.objects.count(), 1)

    def test_identical_inspection_request_is_idempotent(self):
        self.client.force_login(self.user)
        data = {
            "title": "Honda Fit", "brand": "Honda Fit",
            "vin": "JHMGD17507S202261", "operation_type": "tech_inspection",
            "vehicle_category": "M1", "front_photo": uploaded_image(),
            "request_id": "inspection-request-123",
        }
        first = self.client.post("/api/inspections/", data)
        self.assertEqual(first.status_code, 201, first.content)
        data["front_photo"] = uploaded_image()
        data["brand"] = "Changed on retry"
        second = self.client.post("/api/inspections/", data)
        self.assertEqual(second.status_code, 200, second.content)
        self.assertTrue(second.json()["duplicate"])
        self.assertEqual(first.json()["id"], second.json()["id"])
        self.assertEqual(VehicleInspection.objects.count(), 1)

    def test_inspection_file_is_promoted_within_vin_storage_without_duplicate(self):
        inspection = VehicleInspection.objects.create(
            title="Car",
            brand="Car",
            vin="KNAG6412BLA015238",
            branch=self.branch,
            created_by=self.user,
            front_photo=uploaded_image("front.png"),
        )
        staged_path = Path(inspection.front_photo.path)
        self.assertIn("vehicles/KNAG6412BLA015238/staging", inspection.front_photo.name)
        self.assertTrue(staged_path.is_file())

        mirror_inspection(inspection.id)
        inspection.refresh_from_db()

        self.assertIn("vehicles/KNAG6412BLA015238/inspections", inspection.front_photo.name)
        self.assertTrue(inspection.front_photo.name.endswith(".png"))
        self.assertTrue(Path(inspection.front_photo.path).is_file())
        self.assertFalse(staged_path.exists())

    def test_invalid_vehicle_identifier_is_rejected(self):
        self.client.force_login(self.user)
        response = self.client.post("/api/inspections/", {"brand": "Car", "vin": "bad vin!"})
        self.assertEqual(response.status_code, 400)

    def test_missing_price_blocks_inspection(self):
        self.client.force_login(self.user)
        InspectionPrice.objects.filter(
            operation_type="tech_inspection", vehicle_category="N3"
        ).delete()
        response = self.client.post("/api/inspections/", {
            "brand": "Car", "vin": "KNAG6412BLA015238",
            "operation_type": "tech_inspection", "vehicle_category": "N3",
        })
        self.assertEqual(response.status_code, 409)

    def test_detach_removes_archived_application_copy(self):
        inspection = VehicleInspection.objects.create(
            title="Car", brand="Car", vin="KNAG6412BLA015238",
            branch=self.branch, created_by=self.user,
        )
        application = save_client_application(
            inspection.vin, "Test", "123", "+996555111222", "Car", "01KG001", "2020",
            uploaded_pdf(), uploaded_image("signature.png"),
        )
        application.inspection = inspection
        application.save(update_fields=["inspection"])
        inspection.application_pdf.save("linked.pdf", uploaded_pdf(), save=True)
        mirror_inspection(inspection.id)
        inspection.refresh_from_db()
        archived_copy = Path(inspection.application_pdf.path)
        self.assertTrue(archived_copy.exists())

        with self.captureOnCommitCallbacks(execute=True):
            detach_application(application)
        with patch("inspections.background_tasks.notify_telegram_inspection_created"):
            process_next_postprocessing_job()
        inspection.refresh_from_db()
        self.assertFalse(inspection.application_pdf)
        self.assertFalse(archived_copy.exists())
        self.assertTrue(Path(application.pdf.path).exists())

    def test_postprocessing_job_is_durable_and_retryable(self):
        inspection = VehicleInspection.objects.create(
            title="Car", brand="Car", vin="KNAG6412BLA015238",
            branch=self.branch, created_by=self.user,
        )
        schedule_inspection_postprocessing(inspection.id, "https://example.test")
        with patch("inspections.background_tasks.mirror_inspection", side_effect=RuntimeError("disk")):
            self.assertTrue(process_next_postprocessing_job())
        job = InspectionPostprocessJob.objects.get(inspection=inspection)
        self.assertIsNone(job.completed_at)
        self.assertIn("disk", job.last_error)
        job.available_at = timezone.now()
        job.save(update_fields=["available_at"])
        with patch("inspections.background_tasks.notify_telegram_inspection_created"):
            self.assertTrue(process_next_postprocessing_job())
        job.refresh_from_db()
        self.assertIsNotNone(job.completed_at)


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
    def setUp(self):
        self.branch = Branch.objects.create(name="Preview branch")
        self.user = get_user_model().objects.create_user("preview", password="A-safe-password-123")
        self.user.profile.branch = self.branch
        self.user.profile.save(update_fields=["branch"])
        self.client.force_login(self.user)

    def test_preview_is_full_hd_sized_webp_and_keeps_original(self):
        with tempfile.TemporaryDirectory() as media_root:
            source = Path(media_root) / "inspections" / "front" / "large.jpg"
            source.parent.mkdir(parents=True)
            Image.new("RGB", (3000, 2000), "white").save(source, "JPEG", quality=95)
            original_size = source.stat().st_size
            VehicleInspection.objects.create(
                brand="Car", vin="KNAG6412BLA015238", branch=self.branch,
                created_by=self.user, front_photo="inspections/front/large.jpg",
            )

            with override_settings(MEDIA_ROOT=media_root):
                response = self.client.get("/api/photo-preview/inspections/front/large.jpg")
                preview_bytes = b"".join(response.streaming_content)

            self.assertEqual(response.status_code, 200)
            self.assertEqual(response["Content-Type"], "image/webp")
            with Image.open(io.BytesIO(preview_bytes)) as preview:
                self.assertEqual(preview.format, "WEBP")
                self.assertLessEqual(max(preview.size), 1920)
            self.assertEqual(source.stat().st_size, original_size)

    def test_preview_supports_mirrored_vehicle_photos(self):
        with tempfile.TemporaryDirectory() as media_root:
            relative_path = (
                "vehicles/KMFXKS7BPVU138887/inspections/"
                "2026-08-24_092231_conversion_720/photos/front_photo.jpg"
            )
            source = Path(media_root) / relative_path
            source.parent.mkdir(parents=True)
            Image.new("RGB", (1600, 1200), "white").save(source, "JPEG", quality=85)
            VehicleInspection.objects.create(
                brand="Car", vin="KMFXKS7BPVU138887", branch=self.branch,
                created_by=self.user, front_photo=relative_path,
            )

            with override_settings(MEDIA_ROOT=media_root):
                response = self.client.get(f"/api/photo-preview/{relative_path}")
                preview_bytes = b"".join(response.streaming_content)

            self.assertEqual(response.status_code, 200)
            with Image.open(io.BytesIO(preview_bytes)) as preview:
                self.assertEqual(preview.format, "WEBP")

    def test_preview_requires_authentication(self):
        response = Client().get("/api/photo-preview/vehicles/unknown/photo.jpg")
        self.assertEqual(response.status_code, 401)


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
        milestone = self.client.get("/api/milestones/1000/").json()
        self.assertIsNone(milestone["total"])

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

    def test_report_total_is_not_limited_to_first_300_rows(self):
        VehicleInspection.objects.bulk_create([
            VehicleInspection(
                title=f"Car {index}", brand="Car", vin=f"VIN{index:014d}",
                amount=850, branch=self.branch, created_by=self.user,
            )
            for index in range(301)
        ])
        response = self.client.get("/api/inspections/", {
            "date_from": timezone.localdate().isoformat(),
            "date_to": timezone.localdate().isoformat(),
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["total_count"], 301)
        self.assertEqual(len(response.json()["inspections"]), 300)
        self.assertTrue(response.json()["is_truncated"])

    def test_milestone_is_acknowledged_per_user(self):
        with patch.object(VehicleInspection.objects, "count", return_value=1000):
            first = self.client.get("/api/milestones/1000/")
            acknowledged = self.client.post("/api/milestones/1000/")
            after = self.client.get("/api/milestones/1000/")

        self.assertTrue(first.json()["show"])
        self.assertFalse(acknowledged.json()["show"])
        self.assertTrue(acknowledged.json()["acknowledged"])
        self.assertFalse(after.json()["show"])

    def test_smile_greeting_is_only_for_ilim_and_is_acknowledged(self):
        self.assertFalse(self.client.get("/api/greetings/ilim-smile/").json()["show"])

        ilim = get_user_model().objects.create_user(
            "ilim",
            password="A-safe-password-123",
        )
        self.client.force_login(ilim)
        first = self.client.get("/api/greetings/ilim-smile/")
        acknowledged = self.client.post("/api/greetings/ilim-smile/")
        after = self.client.get("/api/greetings/ilim-smile/")

        self.assertTrue(first.json()["show"])
        self.assertTrue(acknowledged.json()["acknowledged"])
        self.assertFalse(after.json()["show"])


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
