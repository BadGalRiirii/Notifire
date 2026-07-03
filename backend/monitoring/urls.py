from django.urls import path

from . import views

urlpatterns = [
    path("health/", views.health),
    path("readings/ingest/", views.ingest_reading),
    path("readings/latest/", views.latest_reading),
    path("readings/history/", views.reading_history),
    path("logs/", views.detection_logs),
    path("device/", views.device_state),
]
