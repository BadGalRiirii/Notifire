"""
Account endpoints: register, email verification, login/logout, forgot/reset
password, profile + notification settings, change password/email, delete
account, and push-token registration.

Responses that log someone in return {"token", "user"}; `user.email_verified`
tells the app whether to show the verification screen.
"""
from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.db import transaction
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle, UserRateThrottle

from .emails import CodeError, check_code, issue_code
from .models import EmailCode, PushDevice
from .serializers import (
    ChangeEmailSerializer,
    ChangePasswordSerializer,
    CodeSerializer,
    DeleteAccountSerializer,
    ForgotPasswordSerializer,
    LoginSerializer,
    PushTokenSerializer,
    RegisterSerializer,
    ResetPasswordSerializer,
    UserSerializer,
)

User = get_user_model()


class AuthThrottle(AnonRateThrottle):
    """Per-IP limit on login/register/reset to slow down guessing."""

    scope = "auth"


class CodeThrottle(UserRateThrottle):
    """Per-user limit on code checks and sensitive account changes."""

    scope = "auth"


def _auth_response(user, status_code=status.HTTP_200_OK, **extra):
    token, _ = Token.objects.get_or_create(user=user)
    return Response({"token": token.key, "user": UserSerializer(user).data, **extra},
                    status=status_code)


def _rotate_token(user):
    """Sign out every phone, then issue a fresh token for this one."""
    Token.objects.filter(user=user).delete()
    PushDevice.objects.filter(user=user).delete()
    return _auth_response(user)


def _code_error(exc):
    return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)


# ------------------------------------------------------- sign up / in ----

@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthThrottle])
def register(request):
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    email_sent = True
    try:
        issue_code(user, EmailCode.Purpose.VERIFY)
    except CodeError:
        email_sent = False  # app offers "Resend code"
    return _auth_response(user, status.HTTP_201_CREATED, email_sent=email_sent)


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthThrottle])
def login(request):
    serializer = LoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = authenticate(
        request,
        username=serializer.validated_data["email"].strip().lower(),
        password=serializer.validated_data["password"],
    )
    if user is None:
        return Response({"detail": "Incorrect email or password."},
                        status=status.HTTP_400_BAD_REQUEST)
    return _auth_response(user)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout(request):
    """Sign out this phone: revoke the token and stop its notifications."""
    token = request.data.get("push_token")
    if token:
        PushDevice.objects.filter(user=request.user, token=token).delete()
    Token.objects.filter(user=request.user).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


# ------------------------------------------------------ verification ----

@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([CodeThrottle])
def verify_email(request):
    serializer = CodeSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    profile = request.user.profile
    if profile.email_verified:
        return Response(UserSerializer(request.user).data)
    try:
        check_code(request.user, EmailCode.Purpose.VERIFY, serializer.validated_data["code"])
    except CodeError as exc:
        return _code_error(exc)
    profile.email_verified = True
    profile.save(update_fields=["email_verified"])
    return Response(UserSerializer(request.user).data)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def resend_verification(request):
    if request.user.profile.email_verified:
        return Response({"detail": "Your email is already verified."})
    try:
        issue_code(request.user, EmailCode.Purpose.VERIFY)
    except CodeError as exc:
        return _code_error(exc)
    return Response({"detail": f"We sent a new code to {request.user.email}."})


# -------------------------------------------------- forgot password ----

@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthThrottle])
def forgot_password(request):
    serializer = ForgotPasswordSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = User.objects.filter(username=serializer.validated_data["email"].strip().lower()).first()
    if user is not None:
        try:
            issue_code(user, EmailCode.Purpose.RESET)
        except CodeError:
            pass  # same response either way — don't reveal which emails exist
    return Response({"detail": "If an account exists for that email, we sent a reset code to it."})


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthThrottle])
def reset_password(request):
    serializer = ResetPasswordSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    user = User.objects.filter(username=data["email"].strip().lower()).first()
    if user is None:
        return Response({"detail": "This code has expired. Request a new one."},
                        status=status.HTTP_400_BAD_REQUEST)
    try:
        validate_password(data["new_password"], user)
    except ValidationError as exc:
        return Response({"new_password": exc.messages}, status=status.HTTP_400_BAD_REQUEST)
    try:
        check_code(user, EmailCode.Purpose.RESET, data["code"])
    except CodeError as exc:
        return _code_error(exc)

    with transaction.atomic():
        user.set_password(data["new_password"])
        user.save(update_fields=["password"])
        # Receiving the code proves they own the inbox.
        user.profile.email_verified = True
        user.profile.save(update_fields=["email_verified"])
    return _rotate_token(user)


# ------------------------------------------------------------ profile ----

@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def me(request):
    """GET profile + notification settings, PATCH {name, notify_*},
    DELETE {password} to permanently delete the account."""
    if request.method == "GET":
        return Response(UserSerializer(request.user).data)

    if request.method == "PATCH":
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(UserSerializer(request.user).data)

    serializer = DeleteAccountSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    if not request.user.check_password(serializer.validated_data["password"]):
        return Response({"password": ["Your password is incorrect."]},
                        status=status.HTTP_400_BAD_REQUEST)
    request.user.delete()  # cascades: detectors, readings, logs, tokens, devices
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([CodeThrottle])
def change_password(request):
    serializer = ChangePasswordSerializer(data=request.data, context={"request": request})
    serializer.is_valid(raise_exception=True)
    request.user.set_password(serializer.validated_data["new_password"])
    request.user.save(update_fields=["password"])
    return _rotate_token(request.user)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([CodeThrottle])
def change_email(request):
    """Step 1: {password, new_email} → emails a code to the new address."""
    serializer = ChangeEmailSerializer(data=request.data, context={"request": request})
    serializer.is_valid(raise_exception=True)
    new_email = serializer.validated_data["new_email"]
    try:
        issue_code(request.user, EmailCode.Purpose.CHANGE_EMAIL, new_email=new_email)
    except CodeError as exc:
        return _code_error(exc)
    return Response({"detail": f"We sent a code to {new_email}."})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([CodeThrottle])
def confirm_change_email(request):
    """Step 2: {code} → switches the account to the new email."""
    serializer = CodeSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    try:
        entry = check_code(request.user, EmailCode.Purpose.CHANGE_EMAIL,
                           serializer.validated_data["code"])
    except CodeError as exc:
        return _code_error(exc)
    if User.objects.filter(username=entry.new_email).exclude(pk=request.user.pk).exists():
        return Response({"detail": "An account with this email already exists."},
                        status=status.HTTP_400_BAD_REQUEST)
    user = request.user
    user.username = user.email = entry.new_email
    user.save(update_fields=["username", "email"])
    user.profile.email_verified = True
    user.profile.save(update_fields=["email_verified"])
    return Response(UserSerializer(user).data)


# --------------------------------------------------------------- push ----

@api_view(["POST"])
@permission_classes([IsAuthenticated])
def register_push(request):
    """Store this phone's FCM token (moves it over if another account had it)."""
    serializer = PushTokenSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    PushDevice.objects.update_or_create(token=serializer.validated_data["token"],
                                        defaults={"user": request.user})
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def unregister_push(request):
    serializer = PushTokenSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    PushDevice.objects.filter(user=request.user, token=serializer.validated_data["token"]).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)
