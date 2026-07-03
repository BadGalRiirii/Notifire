from django.contrib import admin

from .models import DetectionLog, DeviceState, SensorReading


@admin.register(SensorReading)
class SensorReadingAdmin(admin.ModelAdmin):
    list_display = ("created_at", "level", "ppm", "temperature", "humidity", "mq5_enabled", "source")
    list_filter = ("level", "source")


@admin.register(DetectionLog)
class DetectionLogAdmin(admin.ModelAdmin):
    list_display = ("created_at", "level", "message")
    list_filter = ("level",)


@admin.register(DeviceState)
class DeviceStateAdmin(admin.ModelAdmin):
    list_display = ("mq5_enabled", "updated_at")
