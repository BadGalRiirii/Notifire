from rest_framework import serializers

from .models import DetectionLog, DeviceState, SensorReading


class SensorReadingSerializer(serializers.ModelSerializer):
    class Meta:
        model = SensorReading
        fields = [
            "id", "ppm", "temperature", "humidity",
            "mq5_enabled", "level", "source", "created_at",
        ]
        read_only_fields = ["id", "level", "created_at"]


class IngestSerializer(serializers.Serializer):
    """Payload the ESP32 / simulator POSTs."""

    ppm = serializers.FloatField(required=False, allow_null=True, min_value=0)
    temperature = serializers.FloatField(min_value=-40, max_value=125)
    humidity = serializers.FloatField(min_value=0, max_value=100)
    source = serializers.CharField(required=False, default="esp32", max_length=32)


class DetectionLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = DetectionLog
        fields = ["id", "level", "message", "ppm", "temperature", "humidity", "created_at"]


class DeviceStateSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceState
        fields = ["mq5_enabled", "updated_at"]
