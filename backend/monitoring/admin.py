from django.contrib import admin

from .models import DetectionLog, Detector, DetectorMember, SensorReading


class DetectorMemberInline(admin.TabularInline):
    model = DetectorMember
    extra = 0
    fields = ("email", "user", "created_at")
    readonly_fields = ("created_at",)
    raw_id_fields = ("user",)


@admin.register(Detector)
class DetectorAdmin(admin.ModelAdmin):
    inlines = [DetectorMemberInline]
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
