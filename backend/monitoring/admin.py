from django.contrib import admin

from .models import DetectionLog, Detector, SensorReading


@admin.register(Detector)
class DetectorAdmin(admin.ModelAdmin):
    list_display = ("room", "name", "owner", "code", "mq5_enabled", "last_seen_at")
    search_fields = ("room", "name", "code", "owner__username")
    readonly_fields = ("code",)


@admin.register(SensorReading)
class SensorReadingAdmin(admin.ModelAdmin):
    list_display = ("created_at", "detector", "level", "gas", "temperature", "humidity", "mq5_enabled")
    list_filter = ("level", "detector")


@admin.register(DetectionLog)
class DetectionLogAdmin(admin.ModelAdmin):
    list_display = ("created_at", "detector", "level", "message")
    list_filter = ("level", "detector")
