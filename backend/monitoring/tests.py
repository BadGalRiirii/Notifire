import re
from datetime import timedelta
from io import StringIO
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from . import notifications
from .models import Detector, EmailCode, PushDevice

PASSWORD = "s3cure-pass-42"


def last_code():
    """The 6-digit code from the most recent email."""
    return re.search(r"\b(\d{6})\b", mail.outbox[-1].body).group(1)


class ApiTestCase(TestCase):
    def setUp(self):
        cache.clear()  # reset throttles between tests
        mail.outbox.clear()
        self.client = APIClient()
        # Never hit Firebase in tests; record what would be sent instead.
        patcher = mock.patch.object(notifications, "_executor")
        self.executor = patcher.start()
        self.addCleanup(patcher.stop)

    def register(self, email="maria@example.com", name="Maria", password=PASSWORD, verify=True):
        r = self.client.post("/api/auth/register/",
                             {"name": name, "email": email, "password": password}, format="json")
        assert r.status_code == 201, r.content
        token = r.json()["token"]
        if verify:
            self.auth(token)
            v = self.client.post("/api/auth/verify-email/", {"code": last_code()}, format="json")
            assert v.status_code == 200, v.content
        return token

    def auth(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token}")

    def ingest(self, code, **payload):
        body = {"gas": 800, "temperature": 28.0, "humidity": 70.0, **payload}
        return APIClient().post("/api/readings/ingest/", body, format="json",
                                HTTP_X_DETECTOR_CODE=code)

    def pushes(self):
        """Alerts handed to the push pool: list of (tokens, Alert)."""
        return [c.args[1:] for c in self.executor.submit.call_args_list]


class AccountTests(ApiTestCase):
    def test_register_sends_code_and_blocks_until_verified(self):
        r = self.client.post("/api/auth/register/",
                             {"name": "Maria", "email": "Maria@Example.com", "password": PASSWORD},
                             format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertFalse(r.json()["user"]["email_verified"])
        self.assertTrue(r.json()["email_sent"])
        self.assertEqual(mail.outbox[0].to, ["maria@example.com"])
        self.assertNotIn(last_code(), EmailCode.objects.get().code_hash)  # only a hash stored

        self.auth(r.json()["token"])
        self.assertEqual(self.client.get("/api/detectors/").status_code, 403)
        v = self.client.post("/api/auth/verify-email/", {"code": last_code()}, format="json")
        self.assertTrue(v.json()["email_verified"])
        self.assertEqual(self.client.get("/api/detectors/").status_code, 200)

    def test_wrong_codes_are_limited(self):
        self.auth(self.register(verify=False))
        code = last_code()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            r = self.client.post("/api/auth/verify-email/", {"code": wrong}, format="json")
            self.assertEqual(r.status_code, 400)
        # Even the right code is refused after 5 wrong tries.
        r = self.client.post("/api/auth/verify-email/", {"code": code}, format="json")
        self.assertIn("Too many", r.json()["detail"])

    def test_expired_code_rejected_and_resend_has_cooldown(self):
        self.auth(self.register(verify=False))
        self.assertEqual(self.client.post("/api/auth/resend-code/").status_code, 400)  # too soon
        EmailCode.objects.update(created_at=timezone.now() - timedelta(minutes=2),
                                 expires_at=timezone.now() - timedelta(seconds=1))
        r = self.client.post("/api/auth/verify-email/", {"code": last_code()}, format="json")
        self.assertIn("expired", r.json()["detail"])
        self.assertEqual(self.client.post("/api/auth/resend-code/").status_code, 200)
        r = self.client.post("/api/auth/verify-email/", {"code": last_code()}, format="json")
        self.assertTrue(r.json()["email_verified"])

    def test_login(self):
        self.register()
        r = self.client.post("/api/auth/login/", {"email": "maria@example.com", "password": PASSWORD},
                             format="json")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["user"]["email_verified"])
        r = self.client.post("/api/auth/login/", {"email": "maria@example.com", "password": "nope-nope"},
                             format="json")
        self.assertEqual(r.status_code, 400)

    def test_register_rejects_duplicates_and_weak_passwords(self):
        self.register()
        r = self.client.post("/api/auth/register/",
                             {"name": "X", "email": "maria@example.com", "password": PASSWORD}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/auth/register/",
                             {"name": "X", "email": "b@example.com", "password": "12345678"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_login_is_rate_limited(self):
        for _ in range(10):
            self.client.post("/api/auth/login/", {"email": "x@example.com", "password": "bad-pass-1"},
                             format="json")
        r = self.client.post("/api/auth/login/", {"email": "x@example.com", "password": "bad-pass-1"},
                             format="json")
        self.assertEqual(r.status_code, 429)

    def test_forgot_and_reset_password(self):
        old_token = self.register()
        anon = APIClient()
        r = anon.post("/api/auth/forgot-password/", {"email": "nobody@example.com"}, format="json")
        self.assertEqual(r.status_code, 200)  # same answer for unknown emails
        sent_before = len(mail.outbox)
        anon.post("/api/auth/forgot-password/", {"email": "maria@example.com"}, format="json")
        self.assertEqual(len(mail.outbox), sent_before + 1)

        r = anon.post("/api/auth/reset-password/",
                      {"email": "maria@example.com", "code": last_code(), "new_password": "brand-new-pass-7"},
                      format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertNotEqual(r.json()["token"], old_token)  # other phones signed out
        r = anon.post("/api/auth/login/", {"email": "maria@example.com", "password": "brand-new-pass-7"},
                      format="json")
        self.assertEqual(r.status_code, 200)

    def test_settings_name_and_notification_toggles(self):
        self.auth(self.register())
        me = self.client.get("/api/auth/me/").json()
        self.assertEqual((me["notify_danger"], me["notify_warning"], me["notify_offline"]),
                         (True, False, True))
        r = self.client.patch("/api/auth/me/", {"name": "Maria C.", "notify_warning": True,
                                                "notify_offline": False}, format="json")
        self.assertEqual(r.json()["name"], "Maria C.")
        self.assertTrue(r.json()["notify_warning"])
        self.assertFalse(r.json()["notify_offline"])
        r = self.client.patch("/api/auth/me/", {"email": "hack@example.com"}, format="json")
        self.assertEqual(r.json()["email"], "maria@example.com")  # email not editable here

    def test_change_password_rotates_token(self):
        token = self.register()
        self.auth(token)
        r = self.client.post("/api/auth/change-password/",
                             {"current_password": "wrong", "new_password": "another-pass-9"}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/auth/change-password/",
                             {"current_password": PASSWORD, "new_password": "another-pass-9"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self.client.get("/api/auth/me/").status_code, 401)  # old token revoked
        self.auth(r.json()["token"])
        self.assertEqual(self.client.get("/api/auth/me/").status_code, 200)

    def test_change_email_requires_password_and_code(self):
        self.auth(self.register())
        self.register(email="taken@example.com", verify=False)
        self.auth(APIClient().post("/api/auth/login/", {"email": "maria@example.com", "password": PASSWORD},
                                   format="json").json()["token"])
        r = self.client.post("/api/auth/change-email/", {"password": PASSWORD, "new_email": "taken@example.com"},
                             format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/auth/change-email/", {"password": "wrong", "new_email": "new@example.com"},
                             format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/auth/change-email/", {"password": PASSWORD, "new_email": "New@Example.com"},
                             format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(mail.outbox[-1].to, ["new@example.com"])
        r = self.client.post("/api/auth/change-email/confirm/", {"code": last_code()}, format="json")
        self.assertEqual(r.json()["email"], "new@example.com")
        r = APIClient().post("/api/auth/login/", {"email": "new@example.com", "password": PASSWORD}, format="json")
        self.assertEqual(r.status_code, 200)

    def test_delete_account(self):
        self.auth(self.register())
        d = self.client.post("/api/detectors/", {"room": "Bedroom"}, format="json").json()
        r = self.client.delete("/api/auth/me/", {"password": "wrong"}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.delete("/api/auth/me/", {"password": PASSWORD}, format="json")
        self.assertEqual(r.status_code, 204)
        self.assertFalse(Detector.objects.exists())
        self.assertEqual(self.ingest(d["code"]).status_code, 403)

    def test_logout_revokes_token_and_push(self):
        self.auth(self.register())
        self.client.post("/api/push/register/", {"token": "phone-1"}, format="json")
        self.assertEqual(self.client.post("/api/auth/logout/", {"push_token": "phone-1"},
                                          format="json").status_code, 204)
        self.assertFalse(PushDevice.objects.exists())
        self.assertEqual(self.client.get("/api/auth/me/").status_code, 401)

    def test_endpoints_require_login(self):
        self.assertEqual(self.client.get("/api/detectors/").status_code, 401)
        self.assertEqual(self.client.get("/api/logs/").status_code, 401)
        self.assertEqual(self.client.post("/api/push/register/", {"token": "x"}).status_code, 401)


class DetectorTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.auth(self.register())

    def test_create_detector_generates_unique_code(self):
        a = self.client.post("/api/detectors/", {"room": "Bedroom", "name": "Smoke Alarm 1"}, format="json")
        b = self.client.post("/api/detectors/", {"room": "Living room"}, format="json")
        self.assertEqual(a.status_code, 201, a.content)
        self.assertRegex(a.json()["code"], r"^NF-[A-Z2-9]{4}-[A-Z2-9]{4}$")
        self.assertNotEqual(a.json()["code"], b.json()["code"])
        self.assertEqual(len(self.client.get("/api/detectors/").json()), 2)

    def test_room_required_and_name_defaults_from_room(self):
        self.assertEqual(self.client.post("/api/detectors/", {"room": "  "}, format="json").status_code, 400)
        d = self.client.post("/api/detectors/", {"room": "Kitchen"}, format="json").json()
        self.assertEqual((d["room"], d["name"]), ("Kitchen", "Kitchen Detector"))
        r = self.client.patch(f"/api/detectors/{d['id']}/", {"room": "Dining room"}, format="json")
        self.assertEqual(r.json()["room"], "Dining room")

    def test_code_cannot_be_changed_by_client(self):
        d = self.client.post("/api/detectors/", {"room": "Bedroom", "code": "NF-AAAA-AAAA"}, format="json").json()
        self.assertNotEqual(d["code"], "NF-AAAA-AAAA")

    def test_users_cannot_see_each_others_detectors(self):
        d = self.client.post("/api/detectors/", {"room": "Bedroom"}, format="json").json()
        self.ingest(d["code"], gas=2000)
        self.auth(self.register(email="other@example.com"))
        self.assertEqual(self.client.get("/api/detectors/").json(), [])
        self.assertEqual(self.client.get(f"/api/detectors/{d['id']}/").status_code, 404)
        self.assertEqual(self.client.patch(f"/api/detectors/{d['id']}/", {"mq5_enabled": False},
                                           format="json").status_code, 404)
        self.assertEqual(self.client.get("/api/logs/").json(), [])

    def test_device_check_for_bluetooth_setup(self):
        d = self.client.post("/api/detectors/", {"room": "Garage"}, format="json").json()
        r = APIClient().get("/api/device/check/", HTTP_X_DETECTOR_CODE=d["code"])
        self.assertEqual(r.json()["room"], "Garage")
        self.assertEqual(APIClient().get("/api/device/check/",
                                         HTTP_X_DETECTOR_CODE="NF-NOPE-NOPE").status_code, 403)

    def test_ingest_rejects_unknown_code(self):
        self.assertEqual(self.ingest("NF-NOPE-NOPE").status_code, 403)
        self.assertEqual(self.ingest("").status_code, 403)

    def test_ingest_classifies_and_routes_to_detector(self):
        bed = self.client.post("/api/detectors/", {"room": "Bedroom"}, format="json").json()
        living = self.client.post("/api/detectors/", {"room": "Living room"}, format="json").json()
        cases = [
            ({"gas": 800}, "SAFE"),
            ({"gas": 1300}, "WARNING"),
            ({"gas": 1501}, "DANGER"),
            ({"temperature": 40.0}, "WARNING"),  # device uses strict >
            ({"temperature": 40.1}, "DANGER"),
            ({"humidity": 85.5}, "DANGER"),
            ({"humidity": 84.0}, "SAFE"),   # humid CDO day is not a warning
            ({"temperature": None, "humidity": None}, "SAFE"),  # DHT22 error
        ]
        for payload, expected in cases:
            r = self.ingest(bed["code"].lower(), **payload)  # code is case-insensitive
            self.assertEqual(r.status_code, 201, r.content)
            self.assertEqual(r.json()["level"], expected, payload)
        self.ingest(living["code"], gas=100)
        detectors = {d["room"]: d for d in self.client.get("/api/detectors/").json()}
        self.assertEqual(detectors["Bedroom"]["latest_reading"]["level"], "SAFE")
        self.assertEqual(detectors["Living room"]["latest_reading"]["gas"], 100)
        logs = self.client.get("/api/logs/").json()
        self.assertTrue(logs and all(log["room"] == "Bedroom" for log in logs))
        self.assertEqual(self.client.get(f"/api/logs/?detector={living['id']}").json(), [])

    def test_ingest_is_rate_limited_per_detector(self):
        a = self.client.post("/api/detectors/", {"room": "A"}, format="json").json()
        b = self.client.post("/api/detectors/", {"room": "B"}, format="json").json()
        for _ in range(60):
            self.ingest(a["code"])
        self.assertEqual(self.ingest(a["code"]).status_code, 429)
        self.assertEqual(self.ingest(b["code"]).status_code, 201)  # other detector unaffected

    def test_mq5_toggle_is_per_detector_and_echoed_to_esp32(self):
        d = self.client.post("/api/detectors/", {"room": "Kitchen"}, format="json").json()
        self.client.patch(f"/api/detectors/{d['id']}/", {"mq5_enabled": False}, format="json")
        r = self.ingest(d["code"], gas=3000)
        self.assertFalse(r.json()["mq5_enabled"])
        self.assertEqual(r.json()["level"], "SAFE")  # gas ignored while disabled

    def test_deleting_detector_invalidates_its_code(self):
        d = self.client.post("/api/detectors/", {"room": "Garage"}, format="json").json()
        self.assertEqual(self.client.delete(f"/api/detectors/{d['id']}/").status_code, 204)
        self.assertEqual(self.ingest(d["code"]).status_code, 403)


class NotificationTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.auth(self.register())
        self.client.post("/api/push/register/", {"token": "phone-token-1"}, format="json")
        self.kitchen = self.client.post("/api/detectors/", {"room": "Kitchen"}, format="json").json()

    def test_danger_push_names_the_room(self):
        self.ingest(self.kitchen["code"], gas=2000)
        (tokens, alert), = self.pushes()
        self.assertEqual(tokens, ["phone-token-1"])
        self.assertIn("DANGER", alert.title)
        self.assertIn("Kitchen", alert.title)
        self.assertEqual(alert.channel, notifications.CHANNEL_ALARMS)
        self.assertEqual(alert.detector_id, self.kitchen["id"])

    def test_back_to_normal_replaces_alert_once(self):
        self.ingest(self.kitchen["code"], gas=2000)   # DANGER → push
        self.ingest(self.kitchen["code"], gas=400)    # SAFE → "back to normal"
        self.ingest(self.kitchen["code"], gas=400)    # still SAFE → nothing more
        alerts = [alert for _, alert in self.pushes()]
        self.assertEqual([a.kind for a in alerts], ["DANGER", "SAFE"])
        self.assertIn("back to normal", alerts[1].title)
        self.assertEqual(alerts[0].detector_id, alerts[1].detector_id)  # same tag → replaces
        # The "back to normal" message still says what happened, and links to it.
        self.assertIn("Earlier: Smoke or gas detected", alerts[1].body)
        self.assertEqual(alerts[1].log_id, alerts[0].log_id)

    def test_alert_links_to_its_history_entry(self):
        self.ingest(self.kitchen["code"], gas=2000, temperature=31.5)
        (_, alert), = self.pushes()
        r = self.client.get(f"/api/logs/{alert.log_id}/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["room"], "Kitchen")
        self.assertEqual(r.json()["gas"], 2000)        # readings at the moment of the alert
        self.assertEqual(r.json()["temperature"], 31.5)
        self.auth(self.register(email="stranger@example.com"))
        self.assertEqual(self.client.get(f"/api/logs/{alert.log_id}/").status_code, 404)

    def test_no_back_to_normal_without_an_alert(self):
        self.ingest(self.kitchen["code"], gas=1300)   # WARNING, but warning pushes are off
        self.ingest(self.kitchen["code"], gas=400)
        self.assertEqual(self.pushes(), [])

    def test_alert_messages_are_plain(self):
        self.ingest(self.kitchen["code"], gas=2000)
        (_, alert), = self.pushes()
        self.assertIn("Smoke or gas detected", alert.body)

    def test_no_repeat_push_within_cooldown(self):
        for _ in range(3):
            self.ingest(self.kitchen["code"], gas=2000)
        self.assertEqual(len(self.pushes()), 1)

    def test_warning_push_only_when_enabled(self):
        self.ingest(self.kitchen["code"], gas=1300)
        self.assertEqual(self.pushes(), [])
        self.client.patch("/api/auth/me/", {"notify_warning": True}, format="json")
        self.ingest(self.kitchen["code"], gas=1600)  # DANGER resets the log
        self.ingest(self.kitchen["code"], gas=1300)  # WARNING again → push now
        kinds = [alert.kind for _, alert in self.pushes()]
        self.assertEqual(kinds, ["DANGER", "WARNING"])

    def test_danger_push_can_be_disabled(self):
        self.client.patch("/api/auth/me/", {"notify_danger": False}, format="json")
        self.ingest(self.kitchen["code"], gas=2000)
        self.assertEqual(self.pushes(), [])

    def test_token_moves_to_new_account_on_same_phone(self):
        self.auth(self.register(email="other@example.com"))
        self.client.post("/api/push/register/", {"token": "phone-token-1"}, format="json")
        self.assertEqual(PushDevice.objects.get().user.email, "other@example.com")

    def test_offline_and_back_online_alerts(self):
        self.ingest(self.kitchen["code"])
        Detector.objects.update(last_seen_at=timezone.now() - timedelta(minutes=10))
        out = StringIO()
        call_command("check_offline", stdout=out)
        call_command("check_offline", stdout=out)  # second run: no duplicate
        kinds = [alert.kind for _, alert in self.pushes()]
        self.assertEqual(kinds, ["OFFLINE"])
        self.assertIn("1 detector(s) newly offline", out.getvalue())

        self.ingest(self.kitchen["code"])
        kinds = [alert.kind for _, alert in self.pushes()]
        self.assertEqual(kinds, ["OFFLINE", "ONLINE"])

    def test_never_connected_detector_is_not_reported_offline(self):
        call_command("check_offline", stdout=StringIO())
        self.assertEqual(self.pushes(), [])


class FreeTierTests(ApiTestCase):
    """Render free tier: email via Brevo's HTTPS API, offline checks via an
    external scheduler hitting a secret endpoint."""

    def test_codes_are_sent_through_brevo_when_configured(self):
        from django.test import override_settings

        with override_settings(BREVO_API_KEY="test-key", NOTIFIRE_EMAIL_SENDER="alerts@example.com"), \
                mock.patch("urllib.request.urlopen") as urlopen:
            urlopen.return_value.__enter__.return_value.read.return_value = b"{}"
            self.register(email="brevo@example.com", verify=False)
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.brevo.com/v3/smtp/email")
        self.assertEqual(request.get_header("Api-key"), "test-key")
        import json
        body = json.loads(request.data)
        self.assertEqual(body["to"], [{"email": "brevo@example.com"}])
        self.assertEqual(body["sender"]["email"], "alerts@example.com")
        self.assertRegex(body["textContent"], r"\b\d{6}\b")
        self.assertEqual(mail.outbox, [])  # SMTP not used

    def test_cron_endpoint_requires_secret(self):
        from django.test import override_settings

        anon = APIClient()
        self.assertEqual(anon.get("/api/internal/check-offline/").status_code, 404)  # disabled
        with override_settings(NOTIFIRE_CRON_SECRET="s3cret"):
            self.assertEqual(anon.get("/api/internal/check-offline/",
                                      HTTP_X_CRON_SECRET="wrong").status_code, 404)
            r = anon.get("/api/internal/check-offline/", HTTP_X_CRON_SECRET="s3cret")
            self.assertEqual(r.status_code, 200)
            self.assertEqual(r.json()["newly_offline"], 0)

    def test_cron_endpoint_sends_offline_alerts(self):
        from django.test import override_settings

        self.auth(self.register())
        self.client.post("/api/push/register/", {"token": "phone"}, format="json")
        d = self.client.post("/api/detectors/", {"room": "Garage"}, format="json").json()
        self.ingest(d["code"])
        Detector.objects.update(last_seen_at=timezone.now() - timedelta(minutes=10))
        with override_settings(NOTIFIRE_CRON_SECRET="s3cret"):
            r = APIClient().post("/api/internal/check-offline/", HTTP_X_CRON_SECRET="s3cret")
        self.assertEqual(r.json()["newly_offline"], 1)
        self.assertEqual([a.kind for _, a in self.pushes()], ["OFFLINE"])


class HealthTests(TestCase):
    def test_health_checks_database(self):
        r = APIClient().get("/api/health/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["status"], "ok")
