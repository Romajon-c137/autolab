from django.core.management.base import BaseCommand

from inspections.models import VehicleInspection
from inspections.storage_mirror import mirror_inspection


class Command(BaseCommand):
    help = "Write filesystem mirror for existing vehicle inspections."

    def add_arguments(self, parser):
        parser.add_argument("--vin", help="Mirror only one VIN")
        parser.add_argument("--limit", type=int, help="Mirror only the first N inspections")

    def handle(self, *args, **options):
        queryset = VehicleInspection.objects.order_by("created_at", "id")
        if options["vin"]:
            queryset = queryset.filter(vin__iexact=options["vin"].strip())
        if options["limit"]:
            queryset = queryset[:options["limit"]]

        mirrored = 0
        skipped = 0
        for inspection in queryset:
            mirror_dir = mirror_inspection(inspection)
            if mirror_dir is None:
                skipped += 1
                self.stdout.write(f"{inspection.id}: skipped, empty VIN")
                continue

            mirrored += 1
            self.stdout.write(f"{inspection.id}: {inspection.vin} -> {mirror_dir}")

        self.stdout.write(self.style.SUCCESS(f"Mirrored inspections: {mirrored}; skipped: {skipped}"))
