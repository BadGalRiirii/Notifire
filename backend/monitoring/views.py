from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from . import firebase
from .models import DetectionLog, DeviceState, Level, SensorReading
from .serializers import (
    DetectionLogSerializer,
    DeviceStateSerializer,
    IngestSerializer,
    SensorReadingSerializer,
)
from .services import classify

# Avoid spamming the history log with a row every 2 seconds while an alert
# condition persists: only log a new entry when the level changes, or after
# this cooldown while the same non-safe level continues.
LOG_COOLDOWN_SECONDS = 60


@api_view(["GET"])
def health(request):
    return Response({"status": "ok", "time": timezone.now().isoformat()})


@api_view(["POST"])
def ingest_reading(request):
    """ESP32 (or the simulator) pushes sensor data here."""
    serializer = IngestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    state = DeviceState.load()
    ppm = data.get("ppm")
    if not state.mq5_enabled:
        ppm = None  # sensor disabled from the app — ignore gas readings

    result = classify(ppm, data["temperature"], data["humidity"], state.mq5_enabled)

    reading = SensorReading.objects.create(
        ppm=ppm,
        temperature=data["temperature"],
        humidity=data["humidity"],
        mq5_enabled=state.mq5_enabled,
        level=result.level,
        source=data.get("source", "esp32"),
    )

    log_created = False
    if result.level in (Level.WARNING, Level.DANGER):
        last_log = DetectionLog.objects.first()
        should_log = (
            last_log is None
            or last_log.level != result.level
            or (timezone.now() - last_log.created_at).total_seconds() > LOG_COOLDOWN_SECONDS
        )
        if should_log:
            log = DetectionLog.objects.create(
                level=result.level,
                message=result.message,
                ppm=ppm,
                temperature=data["temperature"],
                humidity=data["humidity"],
                reading=reading,
            )
            log_created = True
            firebase.push_log(DetectionLogSerializer(log).data)

    firebase.push_latest(SensorReadingSerializer(reading).data)

    return Response(
        {
            "reading": SensorReadingSerializer(reading).data,
            "log_created": log_created,
            "mq5_enabled": state.mq5_enabled,  # ESP32 reads this to sync its toggle
        },
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET"])
def latest_reading(request):
    """Dashboard endpoint — latest reading + device state."""
    reading = SensorReading.objects.first()
    state = DeviceState.load()
    return Response(
        {
            "reading": SensorReadingSerializer(reading).data if reading else None,
            "device": DeviceStateSerializer(state).data,
        }
    )


@api_view(["GET"])
def reading_history(request):
    """Recent raw readings (for charts). ?limit=50"""
    try:
        limit = min(int(request.query_params.get("limit", 50)), 500)
    except ValueError:
        limit = 50
    qs = SensorReading.objects.all()[:limit]
    return Response(SensorReadingSerializer(qs, many=True).data)


@api_view(["GET"])
def detection_logs(request):
    """History logs — WARNING and DANGER only. Optional ?level=WARNING|DANGER, ?limit=100"""
    level = request.query_params.get("level")
    try:
        limit = min(int(request.query_params.get("limit", 100)), 1000)
    except ValueError:
        limit = 100
    qs = DetectionLog.objects.all()
    if level in (Level.WARNING, Level.DANGER):
        qs = qs.filter(level=level)
    return Response(DetectionLogSerializer(qs[:limit], many=True).data)


@api_view(["GET", "POST"])
def device_state(request):
    """GET current device state, or POST {"mq5_enabled": true|false} to toggle."""
    state = DeviceState.load()
    if request.method == "POST":
        enabled = request.data.get("mq5_enabled")
        if not isinstance(enabled, bool):
            return Response(
                {"detail": "mq5_enabled (boolean) is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        state.mq5_enabled = enabled
        state.save()
        firebase.push_device_state(DeviceStateSerializer(state).data)
    return Response(DeviceStateSerializer(state).data)
