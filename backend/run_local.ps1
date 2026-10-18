# Run the NotiFire server on this PC for the ESP32s and phones on your Wi-Fi.
#
#   cd backend
#   .\run_local.ps1
#
# Uses Waitress (a fixed pool of threads) instead of `manage.py runserver`, so
# database connections to Supabase are reused instead of opened for every
# request — each upload answers in well under a second instead of ~2–3 s.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$env:DB_CONN_MAX_AGE = "60"          # reuse DB connections (safe with a fixed thread pool)
.\venv\Scripts\python.exe manage.py migrate --noinput
.\venv\Scripts\python.exe manage.py collectstatic --noinput | Out-Null
Write-Host "NotiFire server running on http://0.0.0.0:8000  (Ctrl+C to stop)"
.\venv\Scripts\waitress-serve.exe --listen=0.0.0.0:8000 --threads=8 notifire_backend.wsgi:application
