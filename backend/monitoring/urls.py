from django.urls import path

from . import accounts, exports, views

urlpatterns = [
    path("health/", views.health),
    path("internal/check-offline/", views.internal_check_offline),  # external scheduler
    # accounts
    path("auth/register/", accounts.register),
    path("auth/login/", accounts.login),
    path("auth/logout/", accounts.logout),
    path("auth/verify-email/", accounts.verify_email),
    path("auth/resend-code/", accounts.resend_verification),
    path("auth/forgot-password/", accounts.forgot_password),
    path("auth/reset-password/", accounts.reset_password),
    path("auth/me/", accounts.me),
    path("auth/change-password/", accounts.change_password),
    path("auth/change-email/", accounts.change_email),
    path("auth/change-email/confirm/", accounts.confirm_change_email),
    path("push/register/", accounts.register_push),
    path("push/unregister/", accounts.unregister_push),
    # detectors (owned by the logged-in, email-verified user)
    path("detectors/", views.DetectorList.as_view()),
    path("detectors/<int:pk>/", views.DetectorDetail.as_view()),
    path("detectors/<int:pk>/members/", views.detector_members),
    path("detectors/<int:pk>/members/me/", views.leave_detector),
    path("detectors/<int:pk>/members/<int:member_id>/", views.detector_member_detail),
    path("detectors/<int:pk>/readings/", views.detector_readings),
    path("detectors/<int:pk>/readings/export/", exports.export_readings),
    path("logs/", views.detection_logs),
    path("logs/export/", exports.export_logs),
    path("logs/<int:pk>/", views.detection_log_detail),
    # ESP32 → server (authenticated by X-Detector-Code header)
    path("device/check/", views.device_check),
    path("readings/ingest/", views.ingest_reading),
]
