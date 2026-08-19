import json
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.files import File
from django.core.management.base import BaseCommand
from django.utils.dateparse import parse_datetime

from inspections.models import Branch, VehicleInspection, VehicleInspectionExtraPhoto
from inspections.storage_mirror import storage_root


class Command(BaseCommand):
    help = "Rebuild missing inspection rows from backend storage mirror."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true", help="Only show what would be restored")
        parser.add_argument("--vin", help="Restore only one VIN")

    def handle(self, *args, **options):
        root = storage_root() / "vehicles"
        if not root.exists():
            self.stdout.write(self.style.WARNING(f"Storage root does not exist: {root}"))
            return

        restored = 0
        skipped = 0
        for inspection_json in sorted(root.glob("*/inspections/*/inspection.json")):
            data = json.loads(inspection_json.read_text(encoding="utf-8"))
            vin = str(data.get("vin", "")).strip().upper()
            if options["vin"] and vin != options["vin"].strip().upper():
                continue

            original_id = data.get("id")
            created_at = parse_datetime(str(data.get("created_at", ""))) if data.get("created_at") else None
            if original_id and VehicleInspection.objects.filter(id=original_id).exists():
                skipped += 1
                continue
            if vin and created_at and VehicleInspection.objects.filter(vin__iexact=vin, created_at=created_at).exists():
                skipped += 1
                continue

            if options["dry_run"]:
                self.stdout.write(f"Would restore #{original_id or '-'} {vin} from {inspection_json}")
                restored += 1
                continue

            inspection = self._create_inspection(data, original_id)
            self._attach_files(inspection, data, inspection_json.parent)
            if created_at:
                VehicleInspection.objects.filter(id=inspection.id).update(created_at=created_at)
                inspection.created_at = created_at

            restored += 1
            self.stdout.write(f"Restored #{inspection.id}: {inspection.vin}")

        self.stdout.write(self.style.SUCCESS(f"Restored: {restored}; skipped: {skipped}"))

    def _create_inspection(self, data, original_id):
        branch = self._branch_from_data(data.get("branch"))
        user = self._user_from_data(data.get("created_by"))
        kwargs = {
            "title": data.get("title", ""),
            "operation_type": data.get("operation_type", VehicleInspection.OPERATION_SBGTS),
            "plate_number": data.get("plate_number", ""),
            "brand": data.get("brand", ""),
            "country": data.get("country", ""),
            "vehicle_category": data.get("vehicle_category", VehicleInspection.CATEGORY_M1),
            "mileage": data.get("mileage"),
            "amount": data.get("amount") or 0,
            "vin": data.get("vin", ""),
            "branch": branch,
            "created_by": user,
        }
        if original_id:
            kwargs["id"] = original_id

        inspection = VehicleInspection.objects.create(**kwargs)
        taken_at = data.get("photo_taken_at") or {}
        for field_name, raw_value in taken_at.items():
            if hasattr(inspection, f"{field_name}_taken_at"):
                setattr(inspection, f"{field_name}_taken_at", parse_datetime(raw_value) if raw_value else None)
        inspection.save()
        return inspection

    def _attach_files(self, inspection, data, inspection_dir):
        files = data.get("files") or {}
        for field_name, relative_path in (files.get("photos") or {}).items():
            self._save_file(getattr(inspection, field_name, None), relative_path)
        for field_name, relative_path in (files.get("documents") or {}).items():
            self._save_file(getattr(inspection, field_name, None), relative_path)
        inspection.save()

        for raw_photo in files.get("extra_photos") or []:
            photo = VehicleInspectionExtraPhoto(inspection=inspection)
            taken_at = raw_photo.get("taken_at")
            if taken_at:
                photo.taken_at = parse_datetime(taken_at)
            self._save_file(photo.image, raw_photo.get("image"))
            photo.save()

    def _save_file(self, field, relative_path):
        if field is None or not relative_path:
            return

        source = storage_root() / relative_path
        if not source.exists():
            return

        with source.open("rb") as source_file:
            field.save(source.name, File(source_file), save=False)

    def _branch_from_data(self, data):
        if not isinstance(data, dict) or not data.get("name"):
            return None
        branch, _ = Branch.objects.get_or_create(name=data["name"], defaults={"is_active": True})
        return branch

    def _user_from_data(self, data):
        if not isinstance(data, dict) or not data.get("login"):
            return None
        return get_user_model().objects.filter(username=data["login"]).first()
