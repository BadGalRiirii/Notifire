import 'package:flutter/material.dart';

/// In-app user manual: short, plain-language sections (kept in step with
/// USER_MANUAL.md in the repository).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('How to use NotiFire')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: const [
          _Intro(),
          SizedBox(height: 12),
          _Section(
            icon: Icons.rocket_launch_outlined,
            title: '1. Getting started',
            initiallyExpanded: true,
            steps: [
              'Create an account with your name, email and a password.',
              'Check your email for a 6-digit code and enter it in the app. (Check Spam if you don\'t see it.)',
              'Tap Allow when the app asks to send notifications — this is how you get fire alerts.',
            ],
          ),
          _Section(
            icon: Icons.add_circle_outline,
            title: '2. Adding a detector',
            steps: [
              'Plug in the detector. Its light blinks when it is ready to be set up.',
              'Light not blinking? Hold the BOOT button on the detector for 5 seconds until it restarts and blinks.',
              'In the app, tap Add detector, choose the room (for example Bedroom) and, if you like, give it a name.',
              'Tap Next. The app finds the detector over Bluetooth — tap it. It beeps 3 times so you know it is the right one.',
              'Choose your home Wi-Fi and type its password — or tap Scan Wi-Fi QR code and point the camera at '
                  'the QR on your router or another phone (Settings → Wi-Fi → Share). Only 2.4 GHz networks work.',
              'The password is remembered on your phone, so the next detector on the same Wi-Fi needs no typing.',
              'Wait for "connected". The room then shows live readings.',
              'Setting up several? Tap Add another detector after each one.',
            ],
          ),
          _Section(
            icon: Icons.palette_outlined,
            title: '3. What the colours mean',
            children: [
              _Status(color: Color(0xFF43A047), label: 'SAFE', text: 'Everything is normal.'),
              _Status(
                  color: Color(0xFFFFB300),
                  label: 'WARNING',
                  text: 'Smoke/gas (above 1200) or temperature (35°C or more) is rising. Check the room.'),
              _Status(
                  color: Color(0xFFE53935),
                  label: 'DANGER',
                  text: 'Smoke/gas above 1500, temperature above 40°C, or humidity above 85%. '
                      'The detector\'s buzzer sounds.'),
              _Status(
                  color: Colors.grey,
                  label: 'OFFLINE',
                  text: 'The detector stopped sending readings — check its power and Wi-Fi.'),
              _Status(
                  color: Colors.blueGrey,
                  label: 'SET UP',
                  text: 'The detector has not been connected yet. Open it and tap Connect device.'),
            ],
          ),
          _Section(
            icon: Icons.notifications_active_outlined,
            title: '4. When you get an alert',
            steps: [
              'If the app is open, a red (danger) or yellow (warning) pop-up appears. Tap View details.',
              'If the app is closed, you get a notification. Tap it to see what happened.',
              'Alert details shows what triggered it, the readings at that moment, and how the room is right now.',
              'Smoke can clear in seconds. When the room is safe again, the alert changes to "back to normal" and still says what happened.',
              'Works anywhere: your phone does not need the home Wi-Fi. On another Wi-Fi or mobile data you still see live readings and get alerts. Only the detector needs the home Wi-Fi.',
              'If Settings shows "Alerts may be delayed", tap Allow so battery saving does not hold back alerts while NotiFire is closed.',
            ],
            note: 'In real danger: get everyone out of the house first, then call 911 (Bureau of Fire Protection). '
                'Do not wait for the app.',
          ),
          _Section(
            icon: Icons.history,
            title: '5. History and exporting',
            steps: [
              'The History tab lists every warning and danger, newest first, with the room it came from.',
              'Use the All / Warning / Danger and room buttons to filter.',
              'Tap any entry to see its details.',
              'Tap Export to save the history as a spreadsheet (opens in Excel or Google Sheets) — '
                  'choose Alerts or All readings, the room and the period, then save it to Drive or send it.',
              'Alert history is kept permanently. Detailed readings (every 5 seconds) are kept for 30 days.',
            ],
          ),
          _Section(
            icon: Icons.sensors,
            title: '6. The smoke sensor switch (MQ-5)',
            steps: [
              'Each detector has an MQ-5 Smoke Sensor switch on its screen.',
              'Turning it off ignores smoke/gas for that detector — useful while cooking with gas. '
                  'The gas alarm on the detector is muted too.',
              'Temperature and humidity alarms keep working. Remember to turn it back on.',
            ],
          ),
          _Section(
            icon: Icons.wifi,
            title: '7. Moving a detector or changing Wi-Fi',
            steps: [
              'Hold the detector\'s BOOT button for 5 seconds until the light blinks.',
              'In the app, open that room → ⋮ menu → Connect device / change Wi-Fi.',
              'To rename a room, use ⋮ → Edit room / name. To remove one, use ⋮ → Delete detector.',
              'Giving a detector to another account? Delete it in your account first, then reset it with BOOT.',
            ],
          ),
          _Section(
            icon: Icons.settings_outlined,
            title: '8. Settings',
            steps: [
              'Change your name, email or password in Settings → Account.',
              'Choose which alerts you get: Danger (recommended on), Warning, and Offline.',
              'Changing your password logs out your other phones for safety.',
            ],
          ),
          _Section(
            icon: Icons.build_outlined,
            title: '9. Troubleshooting',
            children: [
              _Faq(q: 'The app can\'t find my detector',
                  a: 'It only appears while its light is blinking. Hold BOOT for 5 seconds, keep your phone close, '
                      'and make sure Bluetooth is on.'),
              _Faq(q: 'It says my Wi-Fi password is wrong',
                  a: 'Check capital letters and spaces. Use your 2.4 GHz network (not one ending in "5G").'),
              _Faq(q: 'A room shows OFFLINE',
                  a: 'Check the detector has power and your Wi-Fi is working. It reconnects by itself when the Wi-Fi is back.'),
              _Faq(q: 'I don\'t get notifications',
                  a: 'Settings → Notifications → make sure alerts are on. If it says notifications are turned off, tap Turn on.'),
              _Faq(q: 'I didn\'t get the email code',
                  a: 'Look in Spam, then tap Resend code. Codes expire after 15 minutes.'),
              _Faq(q: '"Cannot reach server"',
                  a: 'Check your phone\'s internet. If the service was idle it can take up to a minute to wake up — try again.'),
            ],
          ),
          _Section(
            icon: Icons.health_and_safety_outlined,
            title: '10. Safety',
            steps: [
              'The detector\'s buzzer is the main alarm — it works even without Wi-Fi or the app.',
              'Phone alerts need Wi-Fi and internet, so treat them as an extra layer.',
              'A new smoke/gas sensor needs about 48 hours powered on before its readings are steady.',
              'Test each detector once a month (for example with a puff of gas from an unlit lighter, from a safe distance).',
            ],
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFF7043).withValues(alpha: 0.12),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.local_fire_department, color: Color(0xFFFF7043), size: 36),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'NotiFire watches each room for smoke, gas and heat, sounds the detector\'s alarm, '
                'and tells your phone which room needs attention.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> steps;
  final List<Widget> children;
  final String? note;
  final bool initiallyExpanded;

  const _Section({
    required this.icon,
    required this.title,
    this.steps = const [],
    this.children = const [],
    this.note,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: const Color(0xFFFF7043)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: const Color(0xFFFF7043).withValues(alpha: 0.2),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF7043))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
            ...children,
            if (note != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.emergency, color: Color(0xFFE53935)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(note!, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final Color color;
  final String label;
  final String text;
  const _Status({required this.color, required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(a, style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}
