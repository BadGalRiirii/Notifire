"""
Who can see a detector: its owner plus the household members it was shared
with (DetectorMember). Only the owner can change, delete or share it.
"""
from django.db.models import Q

from .models import Detector, DetectorMember

MAX_MEMBERS = 10  # per detector


def accessible_detectors(user):
    """Detectors this user owns or was given access to."""
    return Detector.objects.filter(Q(owner=user) | Q(members__user=user)).distinct()


def recipients(detector) -> list:
    """Everyone who gets this detector's alerts: owner first, then members."""
    users = [detector.owner]
    for member in detector.members.select_related("user__profile").filter(user__isnull=False):
        if member.user_id != detector.owner_id:
            users.append(member.user)
    return users


def link_pending_invites(user) -> int:
    """Give a user the detectors that were shared with their email before
    they had (or verified) an account. Call only once the email is verified."""
    email = (user.email or "").strip().lower()
    if not email:
        return 0
    return (DetectorMember.objects
            .filter(user__isnull=True, email=email)
            .exclude(detector__owner=user)
            .update(user=user))
