from django.contrib.auth.signals import user_logged_in
from django.contrib.sessions.models import Session
from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import UserProfile


@receiver(post_save, sender="auth.User")
def create_user_profile(sender, instance, created, raw=False, **kwargs):
    # Fixtures contain profiles explicitly. Creating one from the user signal
    # during a raw load produces a duplicate one-to-one row.
    if created and not raw:
        UserProfile.objects.get_or_create(user=instance)


@receiver(user_logged_in)
def keep_single_active_session(sender, request, user, **kwargs):
    profile, _ = UserProfile.objects.get_or_create(user=user)
    new_session_key = request.session.session_key

    if profile.current_session_key and profile.current_session_key != new_session_key:
        Session.objects.filter(session_key=profile.current_session_key).delete()

    profile.current_session_key = new_session_key or ""
    profile.save(update_fields=["current_session_key"])
