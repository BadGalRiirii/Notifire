"""
Django settings for NotiFire backend.

Solar-Powered IoT-Based Smoke and Fire Detection System
Grade 11 STEM 24 - Group 3
"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# SECURITY WARNING: replace in production
SECRET_KEY = os.environ.get(
    "DJANGO_SECRET_KEY",
    "django-insecure-notifire-dev-key-change-me",
)

DEBUG = os.environ.get("DJANGO_DEBUG", "1") == "1"

ALLOWED_HOSTS = ["*"]  # dev only — restrict in production

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "monitoring",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    # CSRF disabled for API simplicity during prototyping (ESP32 posts).
    # Re-enable and use token auth for production.
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "notifire_backend.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "notifire_backend.wsgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

AUTH_PASSWORD_VALIDATORS = []

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Manila"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.AllowAny"],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "UNAUTHENTICATED_USER": None,
}

CORS_ALLOW_ALL_ORIGINS = True  # dev only

# ---------------------------------------------------------------------------
# NotiFire thresholds (from Chapter 3 requirements analysis)
# ---------------------------------------------------------------------------
# DANGER thresholds (validated system requirements)
NOTIFIRE_PPM_DANGER = float(os.environ.get("NOTIFIRE_PPM_DANGER", 1000))       # MQ-5 > 1000 ppm
NOTIFIRE_TEMP_DANGER = float(os.environ.get("NOTIFIRE_TEMP_DANGER", 55))       # DHT22 >= 55 C (EN 54-5 Class C)
NOTIFIRE_HUM_DANGER = float(os.environ.get("NOTIFIRE_HUM_DANGER", 85))         # >= 85 %RH

# WARNING thresholds (early / approaching danger)
NOTIFIRE_PPM_WARNING = float(os.environ.get("NOTIFIRE_PPM_WARNING", 700))
NOTIFIRE_TEMP_WARNING = float(os.environ.get("NOTIFIRE_TEMP_WARNING", 45))
NOTIFIRE_HUM_WARNING = float(os.environ.get("NOTIFIRE_HUM_WARNING", 82))

# ---------------------------------------------------------------------------
# Firebase (optional). If FIREBASE_CREDENTIALS points to a service-account
# JSON file and FIREBASE_DATABASE_URL is set, readings/logs are mirrored to
# Firebase Realtime Database. The system works fully without Firebase.
# ---------------------------------------------------------------------------
FIREBASE_CREDENTIALS = os.environ.get("FIREBASE_CREDENTIALS", "")
FIREBASE_DATABASE_URL = os.environ.get("FIREBASE_DATABASE_URL", "")
