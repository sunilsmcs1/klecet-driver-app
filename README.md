# KLECET Driver app (Flutter)

Same backend as the web tracker (klecet-bus-tracker.netlify.app). Students and parents keep using the website;
only the driver phone uses this app.

## What it does
- No login. First open → big QR button → scan the bus's QR from the admin page. Phone stays linked to that bus.
- Big green ▶ / red ■ button, auto-start when the bus moves (>15 km/h), auto-stop after 15 min standing.
- Keeps tracking with the screen off, during phone calls and in other apps (Android foreground service,
  shows a "KLECET bus tracking" notification).
- Kannada voice prompts (phone's Google TTS; falls back to English), vibration.
- Red screen + GPS button if location is off or only "approximate" is allowed.
- SOS button: marks "Driver needs help" for 10 min and dials the in-charge number.
- Unlink (admin only): long-press the bus number.

## Build the APK
Option A – laptop with Flutter (3.24+) and Android SDK:  `sh build.sh`
Option B – no install: push this folder to a GitHub repo → Actions tab → "Build driver APK" → download the
artifact `klecet-driver-apk`.

## Install on each bus phone
1. Copy app-release.apk to the phone, allow "Install unknown apps", install.
2. Open → allow Location ("While using the app", Precise ON), Notifications, Camera, and "Allow" for
   battery optimisation.
3. Scan the bus QR from admin.html.
4. Phone settings → Apps → KLECET Driver → Battery → Unrestricted (needed on Xiaomi/Vivo/Oppo/Realme;
   also turn on "Autostart" there).
5. Open the app once each morning (after any phone restart).
