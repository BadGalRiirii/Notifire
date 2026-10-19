from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .models import DetectionLog, Detector, DetectorMember, SensorReading
from .services import held_level

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """The logged-in user, including verification state and notification
    preferences (PATCH name / notify_* via /api/auth/me/)."""

    name = serializers.CharField(source="first_name", max_length=150)
    email_verified = serializers.BooleanField(source="profile.email_verified", read_only=True)
    notify_danger = serializers.BooleanField(source="profile.notify_danger", required=False)
    notify_warning = serializers.BooleanField(source="profile.notify_warning", required=False)
    notify_offline = serializers.BooleanField(source="profile.notify_offline", required=False)

    class Meta:
        model = User
        fields = ["id", "name", "email", "email_verified",
                  "notify_danger", "notify_warning", "notify_offline"]
        read_only_fields = ["id", "email"]

    def validate_name(self, value):
        if not value.strip():
            raise serializers.ValidationError("Enter your name.")
        return value.strip()

    def update(self, instance, validated_data):
        profile_data = validated_data.pop("profile", {})
        if "first_name" in validated_data:
            instance.first_name = validated_data["first_name"]
            instance.save(update_fields=["first_name"])
        if profile_data:
            for field, value in profile_data.items():
                setattr(instance.profile, field, value)
            instance.profile.save(update_fields=list(profile_data))
        return instance


class RegisterSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)

    def validate_email(self, value):
        value = value.strip().lower()
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate(self, attrs):
        validate_password(attrs["password"], User(username=attrs["email"], email=attrs["email"],
                                                  first_name=attrs["name"]))
        return attrs

    def create(self, validated_data):
        # Email doubles as the username so login is by email.
        return User.objects.create_user(
            username=validated_data["email"],
            email=validated_data["email"],
            password=validated_data["password"],
            first_name=validated_data["name"].strip(),
        )


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)


def _check_new_password(password, user):
    validate_password(password, user)
    return password


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate(self, attrs):
        user = self.context["request"].user
        if not user.check_password(attrs["current_password"]):
            raise serializers.ValidationError({"current_password": "Your current password is incorrect."})
        _check_new_password(attrs["new_password"], user)
        return attrs


class ChangeEmailSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True)
    new_email = serializers.EmailField()

    def validate_new_email(self, value):
        value = value.strip().lower()
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate_password(self, value):
        if not self.context["request"].user.check_password(value):
            raise serializers.ValidationError("Your password is incorrect.")
        return value


class CodeSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=12)


class ForgotPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField()


class ResetPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField(max_length=12)
    new_password = serializers.CharField(write_only=True, min_length=8)


class DeleteAccountSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True)


class PushTokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=512)


class SensorReadingSerializer(serializers.ModelSerializer):
    class Meta:
        model = SensorReading
        fields = ["id", "detector", "gas", "temperature", "humidity", "mq5_enabled", "level", "created_at"]


class DetectorSerializer(serializers.ModelSerializer):
    latest_reading = serializers.SerializerMethodField()
    # What the app shows: the latest reading's level, held at the most
    # severe level of the last minute (see services.ALERT_HOLD).
    status_level = serializers.SerializerMethodField()
    # "owner" or "member" (shared with this user by someone in the household).
    role = serializers.SerializerMethodField()
    owner_name = serializers.SerializerMethodField()

    class Meta:
        model = Detector
        fields = ["id", "room", "name", "code", "mq5_enabled", "last_seen_at", "created_at",
                  "latest_reading", "status_level", "role", "owner_name"]
        read_only_fields = ["id", "code", "last_seen_at", "created_at", "latest_reading",
                            "status_level", "role", "owner_name"]
        # Blank name → "<room> Detector" (see Detector.save).
        extra_kwargs = {"name": {"required": False, "allow_blank": True}}

    def validate_room(self, value):
        if not value.strip():
            raise serializers.ValidationError("Enter the room this detector is in.")
        return value

    def _viewer(self):
        request = self.context.get("request")
        return getattr(request, "user", None)

    def get_role(self, obj):
        viewer = self._viewer()
        return "owner" if viewer is None or obj.owner_id == viewer.pk else "member"

    def get_owner_name(self, obj):
        return obj.owner.first_name or obj.owner.email

    def to_representation(self, obj):
        data = super().to_representation(obj)
        if data["role"] != "owner":
            # The code lets a device report as this detector: owner only.
            data["code"] = ""
        return data

    def get_status_level(self, obj):
        return held_level(obj)

    def get_latest_reading(self, obj):
        reading = obj.readings.first()
        return SensorReadingSerializer(reading).data if reading else None


class IngestSerializer(serializers.Serializer):
    """Payload the ESP32 POSTs. temperature/humidity are null on DHT22 error."""

    gas = serializers.FloatField(required=False, allow_null=True, min_value=0, max_value=4095)
    temperature = serializers.FloatField(allow_null=True, min_value=-40, max_value=125)
    humidity = serializers.FloatField(allow_null=True, min_value=0, max_value=100)


class DetectionLogSerializer(serializers.ModelSerializer):
    detector_name = serializers.CharField(source="detector.name", read_only=True)
    room = serializers.CharField(source="detector.room", read_only=True)

    class Meta:
        model = DetectionLog
        fields = ["id", "detector", "detector_name", "room", "level", "message", "gas",
                  "temperature", "humidity", "created_at"]


class DetectorMemberSerializer(serializers.ModelSerializer):
    """A household member as the owner sees them."""

    name = serializers.SerializerMethodField()
    status = serializers.SerializerMethodField()  # "active" | "pending"

    class Meta:
        model = DetectorMember
        fields = ["id", "email", "name", "status", "created_at"]
        read_only_fields = fields

    def get_name(self, obj):
        return obj.user.first_name if obj.user_id else ""

    def get_status(self, obj):
        return "active" if obj.user_id else "pending"


class AddMemberSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate_email(self, value):
        return value.strip().lower()
