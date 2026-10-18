import logging

from django.db import connection
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle

from . import firebase, notifications
from .models import DetectionLog, Detector, Level
from .serializers import (
    DetectionLogSerializer,
    DetectorSerializer,
    IngestSerializer,
    SensorReadingSerializer,
)
from .services import classify

logger = logging.getLogger(__name__)

# Avoid spamming the history log with a row every few seconds while an alert
# condition persists: only log a new entry when the level changes, or after
# this cooldown while the same non-safe level continues.
LOG_COOLDOWN_SECONDS = 60


class DetectorCodeThrottle(SimpleRateThrottle):
    """Rate limit per detector code (not per IP — a home's detectors share one)."""

    scope = "device"

    def get_cache_key(self, request, view):
        code = request.headers.get("X-Detector-Code", "").strip().upper()
        return self.cache_format % {"scope": self.scope, "ident": code or self.get_ident(request)}


# ---------------------------------------------------------------- health ----

@api_view(["GET"])
@permission_classes([AllowAny])
@throttle_classes([])
def health(request):
    """Used by Render's health check: 503 restarts/flags the service."""
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
    except Exception:  # noqa: BLE001
        logger.exception("Health check: database unreachable")
        return Response({"status": "error", "database": "unreachable"},
                        status=status.HTTP_503_SERVICE_UNAVAILABLE)
    return Response({"status": "ok", "time": timezone.now().isoformat()})


# ------------------------------------------------------------- detectors ----
# Default permissions (settings): logged in AND email verified.

class DetectorList(generics.ListCreateAPIView):
    """GET the user's detectors (with latest reading) / POST {room, name?}."""

    serializer_class = DetectorSerializer

    def get_queryset(self):
        return Detector.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class DetectorDetail(generics.RetrieveUpdateDestroyAPIView):
    """GET / PATCH {room, name, mq5_enabled} / DELETE one detector."""

    serializer_class = DetectorSerializer

    def get_queryset(self):
        return Detector.objects.filter(owner=self.request.user)

    def perform_update(self, serializer):
        detector = serializer.save()
        firebase.push_detector(detector.id, {"mq5_enabled": detector.mq5_enabled})


@api_view(["GET"])
def detector_readings(request, pk):
    """Recent raw readings for one detector (for charts). ?limit=50"""
    detector = get_object_or_404(Detector, pk=pk, owner=request.user)
    try:
        limit = min(int(request.query_params.get("limit", 50)), 500)
    except ValueError:
        limit = 50
    return Response(SensorReadingSerializer(detector.readings.all()[:limit], many=True).data)


@api_view(["GET"])
def detection_logs(request):
    """WARNING/DANGER history across the user's detectors.
    Optional ?level=WARNING|DANGER, ?detector=<id>, ?limit=100"""
    qs = DetectionLog.objects.filter(detector__owner=request.user).select_related("detector")
    level = request.query_params.get("level")
    if level in (Level.WARNING, Level.DANGER):
        qs = qs.filter(level=level)
    detector_id = request.query_params.get("detector")
    if detector_id and detector_id.isdigit():
        qs = qs.filter(detector_id=int(detector_id))
    try:
        limit = min(int(request.query_params.get("limit", 100)), 1000)
    except ValueError:
        limit = 100
    return Response(DetectionLogSerializer(qs[:limit], many=True).data)


@api_view(["GET"])
def detection_log_detail(request, pk):
    """One alert (opened from a notification or History): what triggered it,
    the readings at that moment, and the detector it came from."""
    log = get_object_or_404(DetectionLog.objects.select_related("detector"),
                            pk=pk, detector__owner=request.user)
    return Response(DetectionLogSerializer(log).data)


# ------------------------------------------------------------ ESP32 side ----

def _detector_from_code(request):
    code = request.headers.get("X-Detector-Code", "").strip().upper()
    if not code:
        return None
    return (Detector.objects.select_related("owner__profile")
            .filter(code=code).first())


@api_view(["GET"])
@permission_classes([AllowAny])
@throttle_classes([DetectorCodeThrottle])
def device_check(request):
    """Called by the ESP32 at the end of Bluetooth setup to confirm it can
    reach the server and that its code is valid, before saving settings."""
    detector = _detector_from_code(request)
    if detector is None:
        return Response({"detail": "Unknown detector code."}, status=status.HTTP_403_FORBIDDEN)
    return Response({"room": detector.room, "name": detector.name,
                     "mq5_enabled": detector.mq5_enabled})


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([DetectorCodeThrottle])
def ingest_reading(request):
    """An ESP32 pushes sensor data here, identified by its X-Detector-Code."""
    detector = _detector_from_code(request)
    if detector is None:
        return Response({"detail": "Unknown detector code."}, status=status.HTTP_403_FORBIDDEN)

    serializer = IngestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    gas = data.get("gas") if detector.mq5_enabled else None  # MQ-5 disabled from the app
    result = classify(gas, data["temperature"], data["humidity"], detector.mq5_enabled)

    reading = detector.readings.create(
        gas=gas,
        temperature=data["temperature"],
        humidity=data["humidity"],
        mq5_enabled=detector.mq5_enabled,
        level=result.level,
    )
    was_reported_offline = detector.offline_notified_at is not None
    detector.last_seen_at = reading.created_at
    detector.offline_notified_at = None
    update_fields = ["last_seen_at", "offline_notified_at"]
    if result.level == Level.SAFE and detector.alert_level:
        # The owner was alerted earlier: replace that alert with "back to normal".
        notifications.notify_back_to_normal(detector)
        detector.alert_level = ""
        update_fields.append("alert_level")
    detector.save(update_fields=update_fields)
    if was_reported_offline:
        notifications.notify_back_online(detector)

    log_created = False
    if result.level in (Level.WARNING, Level.DANGER):
        last_log = detector.logs.first()
        should_log = (
            last_log is None
            or last_log.level != result.level
            or (timezone.now() - last_log.created_at).total_seconds() > LOG_COOLDOWN_SECONDS
        )
        if should_log:
            log = detector.logs.create(
                level=result.level,
                message=result.message,
                gas=gas,
                temperature=data["temperature"],
                humidity=data["humidity"],
                reading=reading,
            )
            log_created = True
            if notifications.notify_detection(detector, log):
                detector.alert_level = result.level
                detector.save(update_fields=["alert_level"])
            firebase.push_log(detector.id, DetectionLogSerializer(log).data)

    firebase.push_latest(detector.id, SensorReadingSerializer(reading).data)

    return Response(
        {
            "level": result.level,
            "log_created": log_created,
            "mq5_enabled": detector.mq5_enabled,  # ESP32 reads this to sync its toggle
        },
        status=status.HTTP_201_CREATED,
    )
