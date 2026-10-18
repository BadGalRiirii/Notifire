"""
Django settings for NotiFire backend.

Solar-Powered IoT-Based Smoke and Fire Detection System
Grade 11 STEM 24 - Group 3

Configured entirely through environment variables (backend/.env locally,
the Render dashboard in production). See backend/.env.example.
"""
import os
import sys
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent

try:
    from dotenv import load_dotenv
    load_dotenv(BASE_DIR / ".env")
except ImportError:
    pass


def env_bool(name, default=False):
    return os.environ.get(name, "1" if default else "0").strip().lower() in ("1", "true", "yes")


TESTING = "test" in sys.argv[1:2]

DEBUG = env_bool("DJANGO_DEBUG", False)

_DEV_KEY = "django-insecure-notifire-dev-key-change-me"
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", _DEV_KEY)
if SECRET_KEY == _DEV_KEY and not (DEBUG or TESTING):
    raise ImproperlyConfigured("Set DJANGO_SECRET_KEY (a long random value) in production.")

# Comma-separated, e.g. "192.168.100.89,localhost". Render's own hostname is
# added automatically.
ALLOWED_HOSTS = [h.strip() for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",") if h.strip()]
if os.environ.get("RENDER_EXTERNAL_HOSTNAME"):
    ALLOWED_HOSTS.append(os.environ["RENDER_EXTERNAL_HOSTNAME"])

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework.authtoken",
    "monitoring",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",  # admin only; API uses tokens
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

# ---------------------------------------------------------------------------
# Database — DATABASE_URL (Supabase session pooler) or local SQLite.
# Tests always use SQLite so they never create/drop databases on Supabase.
# ---------------------------------------------------------------------------
DATABASE_URL = "" if TESTING else os.environ.get("DATABASE_URL", "")
if DATABASE_URL:
    import dj_database_url

    DATABASES = {
        "default": dj_database_url.parse(
            DATABASE_URL,
            # 0 = close after each request (needed with runserver's thread per
            # request). Under gunicorn (fixed workers × threads) set ~60 to
            # reuse connections; keep workers × threads under Supabase's
            # 15-client session pool.
            conn_max_age=int(os.environ.get("DB_CONN_MAX_AGE", 0)),
            conn_health_checks=True,
            ssl_require=True,
        )
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

if TESTING:
    # Deliberately slow hashing protects real passwords; tests don't need it.
    PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Manila"
USE_I18N = True
USE_TZ = True

# Static files (admin) served by WhiteNoise: compressed, hashed names and
# far-future cache headers so browsers/CDNs cache them safely.
STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": ("django.contrib.staticfiles.storage.StaticFilesStorage" if (DEBUG or TESTING)
                    else "whitenoise.storage.CompressedManifestStaticFilesStorage"),
    },
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ---------------------------------------------------------------------------
# API: token auth, verified email required by default, rate limits.
# Throttle counters live in each worker's memory (LocMemCache): limits are
# per worker, i.e. a little looser with several workers — no extra DB load.
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    # The app sends "Authorization: Token <key>" after login/register.
    "DEFAULT_AUTHENTICATION_CLASSES": ["rest_framework.authentication.TokenAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
        "monitoring.permissions.IsEmailVerified",
    ],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "60/min",
        "user": "300/min",
        "auth": "10/min",     # login / register / codes / password changes
        "device": "60/min",   # per detector code (ESP32 uploads every ~5 s)
    },
    "UNAUTHENTICATED_USER": "django.contrib.auth.models.AnonymousUser",
}

# ---------------------------------------------------------------------------
# HTTPS (production). NOTIFIRE_FORCE_HTTPS=1 behind Render's TLS proxy.
# ---------------------------------------------------------------------------
FORCE_HTTPS = env_bool("NOTIFIRE_FORCE_HTTPS", False)
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
if FORCE_HTTPS:
    SECURE_SSL_REDIRECT = True
    SECURE_REDIRECT_EXEMPT = [r"^api/health/$"]  # platform health checks
    SECURE_HSTS_SECONDS = 60 * 60 * 24 * 365
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
CSRF_TRUSTED_ORIGINS = [f"https://{h}" for h in ALLOWED_HOSTS if "." in h and not h[0].isdigit()]
# HSTS preload lists only accept domains you own, not *.onrender.com.
SILENCED_SYSTEM_CHECKS = ["security.W021"]

# ---------------------------------------------------------------------------
# Email (verification / reset codes). Gmail: smtp.gmail.com:587 with an
# App Password. Without credentials, emails are printed to the console.
# ---------------------------------------------------------------------------
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")
if TESTING:
    EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
elif EMAIL_HOST_USER and EMAIL_HOST_PASSWORD:
    EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
else:
    EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"
EMAIL_HOST = os.environ.get("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", 587))
EMAIL_USE_TLS = True
EMAIL_TIMEOUT = 15
EMAIL_SEND_ASYNC = not TESTING  # send codes in the background (monitoring/emails.py)

# Brevo (HTTPS email API) — used instead of SMTP when BREVO_API_KEY is set.
# Required on Render's free tier, which blocks SMTP ports 25/465/587.
# The sender address must be verified in Brevo (Senders & IP → Senders).
BREVO_API_KEY = os.environ.get("BREVO_API_KEY", "")
NOTIFIRE_EMAIL_SENDER = os.environ.get("NOTIFIRE_EMAIL_SENDER", EMAIL_HOST_USER or "noreply@notifire.local")
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", f"NotiFire <{EMAIL_HOST_USER or 'noreply@notifire.local'}>")

# ---------------------------------------------------------------------------
# Logging → stdout (Render collects it). Error tracking: set SENTRY_DSN.
# ---------------------------------------------------------------------------
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s: %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "django.request": {"level": "WARNING"},
        "django.server": {"level": "WARNING" if not DEBUG else "INFO"},
    },
}

SENTRY_DSN = os.environ.get("SENTRY_DSN", "")
if SENTRY_DSN and not TESTING:
    import sentry_sdk

    sentry_sdk.init(
        dsn=SENTRY_DSN,
        environment=os.environ.get("SENTRY_ENVIRONMENT", "production"),
        traces_sample_rate=0.05,
        send_default_pii=False,  # no emails / IPs sent to Sentry
    )

# ---------------------------------------------------------------------------
# NotiFire thresholds — DANGER values MUST match the constants flashed on the
# ESP32 (firmware/notifire_esp32/notifire_esp32.ino) so the app and the
# on-device buzzer agree. If you change one, change the other.
# ---------------------------------------------------------------------------
# DANGER thresholds (strictly greater than)
NOTIFIRE_GAS_DANGER = float(os.environ.get("NOTIFIRE_GAS_DANGER", 1500))       # MQ-5 raw ADC > 1500 (0–4095)
NOTIFIRE_TEMP_DANGER = float(os.environ.get("NOTIFIRE_TEMP_DANGER", 40))       # DHT22 > 40 C
NOTIFIRE_HUM_DANGER = float(os.environ.get("NOTIFIRE_HUM_DANGER", 85))         # DHT22 > 85 %RH

# WARNING thresholds (early / approaching danger) — backend/app only.
# Humidity has none on purpose (normal CDO weather is ~75–84 %RH).
NOTIFIRE_GAS_WARNING = float(os.environ.get("NOTIFIRE_GAS_WARNING", 1200))
NOTIFIRE_TEMP_WARNING = float(os.environ.get("NOTIFIRE_TEMP_WARNING", 35))

# A detector silent this long gets an "offline" push (monitoring/offline.py).
NOTIFIRE_OFFLINE_ALERT_MINUTES = int(os.environ.get("NOTIFIRE_OFFLINE_ALERT_MINUTES", 3))

# Shared secret for /api/internal/check-offline/ (sent as X-Cron-Secret by
# the external scheduler). Unset = endpoint disabled.
NOTIFIRE_CRON_SECRET = os.environ.get("NOTIFIRE_CRON_SECRET", "")

# ---------------------------------------------------------------------------
# Firebase — push notifications (FCM) and optional Realtime Database mirror.
# Service-account JSON via FIREBASE_CREDENTIALS_JSON (contents) or
# FIREBASE_CREDENTIALS (file path). See monitoring/firebase.py.
# ---------------------------------------------------------------------------
FIREBASE_CREDENTIALS_JSON = os.environ.get("FIREBASE_CREDENTIALS_JSON", "")
FIREBASE_CREDENTIALS = os.environ.get("FIREBASE_CREDENTIALS", "")
if FIREBASE_CREDENTIALS and not os.path.isabs(FIREBASE_CREDENTIALS):
    FIREBASE_CREDENTIALS = str(BASE_DIR / FIREBASE_CREDENTIALS)  # relative to backend/
FIREBASE_DATABASE_URL = os.environ.get("FIREBASE_DATABASE_URL", "")
