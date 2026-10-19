"""
CSV exports (open in Excel / Google Sheets).

  GET /api/logs/export/?level=&detector=&days=        alert history
  GET /api/detectors/<id>/readings/export/?days=7     raw readings, max 31 days

Times are in the server's local time zone (Asia/Manila). Files start with a
UTF-8 byte-order mark so Excel shows "°C" correctly, and cells that could be
read as spreadsheet formulas are neutralised (room names are user input).
"""
import csv
from datetime import timedelta

from django.http import StreamingHttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.decorators import api_view

from .access import accessible_detectors
from .models import DetectionLog, Detector, Level

MAX_READING_DAYS = 31


class _Echo:
    """File-like object whose write() returns the line (for streaming)."""

    def write(self, value):
        return value


def _safe(value):
    """Stop Excel from running cell contents like '=HYPERLINK(...)'."""
    text = "" if value is None else str(value)
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text


def _num(value, digits):
    return "" if value is None else f"{value:.{digits}f}"


def _days(request, default, maximum=None):
    try:
        days = int(request.query_params.get("days", default))
    except ValueError:
        days = default
    if days <= 0:
        return None  # all time
    return min(days, maximum) if maximum else days


def _csv_response(rows, header, filename):
    writer = csv.writer(_Echo())

    def stream():
        yield "﻿"  # UTF-8 BOM for Excel
        yield writer.writerow(header)
        for row in rows:
            yield writer.writerow([_safe(cell) for cell in row])

    response = StreamingHttpResponse(stream(), content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response


def _stamp():
    return timezone.localtime().strftime("%Y%m%d-%H%M")


@api_view(["GET"])
def export_logs(request):
    """Alert history (WARNING/DANGER) for the user's detectors."""
    qs = (DetectionLog.objects.filter(detector__in=accessible_detectors(request.user))
          .select_related("detector").order_by("-created_at"))
    level = request.query_params.get("level")
    if level in (Level.WARNING, Level.DANGER):
        qs = qs.filter(level=level)
    detector_id = request.query_params.get("detector")
    if detector_id and detector_id.isdigit():
        qs = qs.filter(detector_id=int(detector_id))
    days = _days(request, default=0)
    if days:
        qs = qs.filter(created_at__gte=timezone.now() - timedelta(days=days))

    def rows():
        for log in qs.iterator(chunk_size=500):
            t = timezone.localtime(log.created_at)
            yield [t.strftime("%Y-%m-%d"), t.strftime("%I:%M:%S %p"), log.detector.room,
                   log.detector.name, log.level, log.message, _num(log.gas, 0),
                   _num(log.temperature, 1), _num(log.humidity, 1)]

    header = ["Date", "Time", "Room", "Detector", "Level", "What happened",
              "Smoke/gas level", "Temperature (°C)", "Humidity (%)"]
    return _csv_response(rows(), header, f"notifire-alerts-{_stamp()}.csv")


@api_view(["GET"])
def export_readings(request, pk):
    """Every reading one detector sent, for the last N days (max 31)."""
    detector = get_object_or_404(accessible_detectors(request.user), pk=pk)
    days = _days(request, default=7, maximum=MAX_READING_DAYS) or MAX_READING_DAYS
    qs = (detector.readings.filter(created_at__gte=timezone.now() - timedelta(days=days))
          .order_by("-created_at"))

    def rows():
        for r in qs.iterator(chunk_size=2000):
            t = timezone.localtime(r.created_at)
            yield [t.strftime("%Y-%m-%d"), t.strftime("%I:%M:%S %p"), r.level,
                   _num(r.gas, 0), _num(r.temperature, 1), _num(r.humidity, 1),
                   "on" if r.mq5_enabled else "off"]

    header = ["Date", "Time", "Status", "Smoke/gas level", "Temperature (°C)",
              "Humidity (%)", "MQ-5 sensor"]
    room = "".join(c if c.isalnum() else "-" for c in detector.room.lower()).strip("-") or "detector"
    return _csv_response(rows(), header, f"notifire-{room}-readings-{_stamp()}.csv")
