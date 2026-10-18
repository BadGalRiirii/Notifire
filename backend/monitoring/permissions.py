from rest_framework.permissions import BasePermission


class IsEmailVerified(BasePermission):
    """Detectors, readings and history require a verified email address."""

    message = "Please verify your email address first."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated
                    and getattr(getattr(user, "profile", None), "email_verified", False))
