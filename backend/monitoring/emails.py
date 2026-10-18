"""
One-time email codes for verification, password reset and email change.

Codes are 6 digits, expire after CODE_TTL, allow MAX_ATTEMPTS guesses, and
can be re-sent once per RESEND_COOLDOWN. Only an HMAC of the code (keyed with
SECRET_KEY) is stored, so a database leak does not reveal live codes.
"""
import hashlib
import hmac
import logging
import secrets
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

from django.conf import settings
from django.core.mail import send_mail
from django.utils import timezone
from django.utils.crypto import constant_time_compare

from .models import EmailCode

logger = logging.getLogger(__name__)

CODE_TTL = timedelta(minutes=15)
RESEND_COOLDOWN = timedelta(seconds=60)
MAX_ATTEMPTS = 5

_SUBJECTS = {
    EmailCode.Purpose.VERIFY: "Verify your NotiFire account",
    EmailCode.Purpose.RESET: "Reset your NotiFire password",
    EmailCode.Purpose.CHANGE_EMAIL: "Confirm your new NotiFire email",
}
_INTROS = {
    EmailCode.Purpose.VERIFY: "Welcome to NotiFire! Enter this code in the app to verify your email:",
    EmailCode.Purpose.RESET: "Someone (hopefully you) asked to reset your NotiFire password. Enter this code in the app:",
    EmailCode.Purpose.CHANGE_EMAIL: "Enter this code in the NotiFire app to confirm this as your new email:",
}


# Sending through Gmail takes 1–3 s; do it off the request so registering or
# requesting a code answers immediately (the user can always "Resend code").
_mailer = ThreadPoolExecutor(max_workers=2, thread_name_prefix="mail")


class CodeError(Exception):
    """User-facing problem with a code (wrong, expired, too soon...)."""


def _deliver(subject: str, body: str, to: str, user_id: int, purpose: str) -> None:
    try:
        send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [to])
        logger.info("Sent %s code to user %s", purpose, user_id)
    except Exception:  # noqa: BLE001
        logger.exception("Failed to send %s code to user %s", purpose, user_id)


def _hash(user_id: int, purpose: str, code: str) -> str:
    msg = f"{purpose}:{user_id}:{code}".encode()
    return hmac.new(settings.SECRET_KEY.encode(), msg, hashlib.sha256).hexdigest()


def issue_code(user, purpose: str, new_email: str = "") -> None:
    """Create a fresh code (invalidating older ones) and email it.
    Raises CodeError if asked again within the cooldown."""
    last = EmailCode.objects.filter(user=user, purpose=purpose).first()
    if last and timezone.now() - last.created_at < RESEND_COOLDOWN:
        wait = int((RESEND_COOLDOWN - (timezone.now() - last.created_at)).total_seconds()) + 1
        raise CodeError(f"Please wait {wait} seconds before requesting another code.")

    EmailCode.objects.filter(user=user, purpose=purpose, used=False).update(used=True)
    code = f"{secrets.randbelow(1_000_000):06d}"
    EmailCode.objects.create(
        user=user,
        purpose=purpose,
        new_email=new_email,
        code_hash=_hash(user.id, purpose, code),
        expires_at=timezone.now() + CODE_TTL,
    )

    to = new_email or user.email
    name = user.first_name or "there"
    body = (
        f"Hi {name},\n\n{_INTROS[purpose]}\n\n    {code}\n\n"
        f"The code expires in {int(CODE_TTL.total_seconds() // 60)} minutes. "
        "If you didn't request it, you can ignore this email.\n\n— NotiFire"
    )
    args = (_SUBJECTS[purpose], body, to, user.id, purpose)
    if settings.EMAIL_SEND_ASYNC:
        _mailer.submit(_deliver, *args)
    else:
        _deliver(*args)  # tests: deterministic, lands in mail.outbox now


def check_code(user, purpose: str, code: str) -> EmailCode:
    """Validate and consume the latest code. Raises CodeError if invalid."""
    entry = EmailCode.objects.filter(user=user, purpose=purpose, used=False).first()
    if entry is None or entry.expires_at < timezone.now():
        raise CodeError("This code has expired. Request a new one.")
    if entry.attempts >= MAX_ATTEMPTS:
        raise CodeError("Too many wrong attempts. Request a new code.")

    entry.attempts += 1
    code = "".join(ch for ch in str(code) if ch.isdigit())
    if not constant_time_compare(entry.code_hash, _hash(user.id, purpose, code)):
        entry.save(update_fields=["attempts"])
        left = MAX_ATTEMPTS - entry.attempts
        raise CodeError("Incorrect code." + (f" {left} attempts left." if left else " Request a new code."))

    entry.used = True
    entry.save(update_fields=["attempts", "used"])
    return entry
