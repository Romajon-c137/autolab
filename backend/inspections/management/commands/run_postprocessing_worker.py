import time

from django.core.management.base import BaseCommand
from django.db import close_old_connections

from inspections.background_tasks import process_next_postprocessing_job


class Command(BaseCommand):
    help = "Process durable inspection archive and notification jobs"

    def handle(self, *args, **options):
        self.stdout.write("Inspection postprocessing worker started")
        while True:
            close_old_connections()
            if not process_next_postprocessing_job():
                time.sleep(2)
