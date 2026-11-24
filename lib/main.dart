// KLECET Bus Tracker - Driver app (Flutter)
// No login: the phone is linked to one bus once by scanning the QR code from the admin page.
// Location keeps going in the background (phone calls, screen off) through an Android foreground service.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const sbUrl = 'https://wkcqzcditqvvzdedcgvh.supabase.co';
const sbKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrY3F6Y2RpdHF2dnpkZWRjZ3ZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUxOTIyNzEsImV4cCI6MjExMDc2ODI3MX0.flhneOF2HGnVkHnPLEHM1_B8OEf71NucvAVyAlRX2ig';

const cGrey = Color(0xFF26333A), cGreen = Color(0xFF137A42), cRed = Color(0xFFA81F1F), cBtnGo = Color(0xFF1F9D55), cBtnStop = Color(0xFFD23A3A);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const DriverApp());
}

Future<dynamic> rpc(String fn, Map<String, dynamic> args) async {
  final r = await http
      .post(Uri.parse('$sbUrl/rest/v1/rpc/$fn'),
          headers: {'apikey': sbKey, 'Authorization': 'Bearer $sbKey', 'Content-Type': 'application/json'}, body: jsonEncode(args))
      .timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(r.body);
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KLECET Driver',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFF5B800), brightness: Brightness.dark),
        home: const Root(),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String? bus, key;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() {
          bus = p.getString('bus');
          key = p.getString('key');
          loaded = true;
        }));
  }

  Future<void> link(String b, String k) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('bus', b);
    await p.setString('key', k);
    setState(() { bus = b; key = k; });
  }

  Future<void> unlink() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    setState(() { bus = null; key = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(backgroundColor: cGrey);
    if (bus == null || key == null) return SetupScreen(onLinked: link);
    return DriverScreen(bus: bus!, busKey: key!, onUnlink: unlink);
  }
}

// ---------------- One-time setup: scan the bus QR from the admin page ----------------
class SetupScreen extends StatefulWidget {
  final Future<void> Function(String, String) onLinked;
  const SetupScreen({super.key, required this.onLinked});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool scanning = false, busy = false;
  String msg = '';

  Future<void> handle(String raw) async {
    if (busy) return;
    final u = Uri.tryParse(raw);
    final b = u?.queryParameters['bus'], k = u?.queryParameters['k'];
    if (b == null || k == null) { setState(() => msg = 'Not a bus QR code'); return; }
    setState(() { busy = true; scanning = false; msg = 'Checking…'; });
    try {
      final info = await rpc('driver_info', {'p_bus': b, 'p_key': k});
      if (info == null) { setState(() { msg = 'This QR code is old. Use the latest one from admin.'; busy = false; }); return; }
      await widget.onLinked(b, k);
    } catch (e) {
      setState(() { msg = 'No internet. Try again.'; busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (scanning) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          MobileScanner(onDetect: (cap) {
            final v = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
            if (v != null) handle(v);
          }),
          Positioned(top: 40, right: 16, child: IconButton.filled(onPressed: () => setState(() => scanning = false), icon: const Icon(Icons.close, size: 32))),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: cGrey,
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.directions_bus, size: 96, color: Color(0xFFF5B800)),
            const SizedBox(height: 24),
            SizedBox(
              width: 260, height: 260,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: cGrey, shape: const CircleBorder()),
                onPressed: busy ? null : () => setState(() { scanning = true; msg = ''; }),
                child: const Icon(Icons.qr_code_scanner, size: 140),
              ),
            ),
            const SizedBox(height: 24),
            Text(msg, style: const TextStyle(fontSize: 18, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Driver screen ----------------
class DriverScreen extends StatefulWidget {
  final String bus, busKey;
  final Future<void> Function() onUnlink;
  const DriverScreen({super.key, required this.bus, required this.busKey, required this.onUnlink});
  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class Fix {
  final double lat, lng, acc, speed, head;
  final DateTime t;
  Fix(this.lat, this.lng, this.acc, this.speed, this.head, this.t);
}

class _DriverScreenState extends State<DriverScreen> with WidgetsBindingObserver {
  final tts = FlutterTts();
  StreamSubscription<Position>? sub;
  Timer? tick;
  Fix? last;
  bool running = false, sending = false, gpsWarned = false, precise = true, svcOn = true;
  bool? netOk;
  String? queued, phone;
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0), helpUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? stillSince;
  int fastCount = 0;
  String dbg = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sub?.cancel();
    tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) checkLocation();
  }

  Future<void> start() async {
    final p = await SharedPreferences.getInstance();
    running = p.getBool('tripOn') ?? false;
    await tts.setSpeechRate(0.45);
    try {
      final ok = await tts.isLanguageAvailable('kn-IN');
      await tts.setLanguage(ok == true ? 'kn-IN' : 'en-IN');
    } catch (_) {}
    try {
      final info = await rpc('driver_info', {'p_bus': widget.bus, 'p_key': widget.busKey});
      if (info == null) { await widget.onUnlink(); return; } // bus removed or QR replaced
      phone = (info['phone'] ?? '') as String;
    } catch (_) {}
    await Permission.notification.request();
    if (!await Permission.ignoreBatteryOptimizations.isGranted) await Permission.ignoreBatteryOptimizations.request();
    await checkLocation();
    tick = Timer.periodic(const Duration(seconds: 10), (_) {
      final fresh = last != null && DateTime.now().difference(last!.t).inSeconds < 30;
      if (running && fresh && DateTime.now().difference(lastSent).inSeconds > 35) send('running');
      if (running && !fresh) gpsBad();
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  Future<void> checkLocation() async {
    svcOn = await Geolocator.isLocationServiceEnabled();
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever || !svcOn) { if (mounted) setState(() {}); return; }
    try { precise = (await Geolocator.getLocationAccuracy()) == LocationAccuracyStatus.precise; } catch (_) {}
    if (sub == null) listen();
    if (mounted) setState(() {});
  }

  void listen() {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'KLECET bus tracking',
        notificationText: 'Sharing bus location with students',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    sub = Geolocator.getPositionStream(locationSettings: settings).listen(onFix, onError: (_) => gpsBad());
  }

  Future<void> say(String kn, String en) async {
    HapticFeedback.heavyImpact();
    try {
      final lang = await tts.isLanguageAvailable('kn-IN');
      await tts.speak(lang == true ? kn : en);
    } catch (_) {}
  }

  void gpsBad() {
    if (running && !gpsWarned) { gpsWarned = true; say('ಜಿಪಿಎಸ್ ಇಲ್ಲ', 'No GPS'); }
    if (mounted) setState(() {});
  }

  void onFix(Position p) {
    dbg = '±${p.accuracy.round()} m';
    if (p.accuracy > 100) { gpsBad(); return; } // approximate location is not good enough
    final prev = last;
    var speed = p.speed;
    if ((speed.isNaN || speed <= 0) && prev != null) {
      final dt = DateTime.now().difference(prev.t).inMilliseconds / 1000;
      if (dt > 0) speed = Geolocator.distanceBetween(prev.lat, prev.lng, p.latitude, p.longitude) / dt;
    }
    if (speed.isNaN || speed < 0) speed = 0;
    last = Fix(p.latitude, p.longitude, p.accuracy, speed, p.heading, DateTime.now());
    gpsWarned = false;
    dbg = '${(speed * 3.6).round()} km/h · ±${p.accuracy.round()} m';
    // auto start: faster than ~15 km/h on 3 fixes in a row
    if (!running) { fastCount = speed > 4.2 ? fastCount + 1 : 0; if (fastCount >= 3) setRun(true); }
    if (running) {
      // auto stop: standing still 15 minutes
      if (speed < 0.8) {
        stillSince ??= DateTime.now();
        if (DateTime.now().difference(stillSince!).inMinutes >= 15) setRun(false);
      } else {
        stillSince = null;
      }
      final gap = speed > 1.5 ? 5 : 30;
      if (DateTime.now().difference(lastSent).inSeconds >= gap) send('running');
    }
    if (mounted) setState(() {});
  }

  Future<void> send(String status) async {
    if (sending) { if (status != 'running' || queued == null) queued = status; return; }
    sending = true;
    final f = last;
    final st = (status == 'running' && DateTime.now().isBefore(helpUntil)) ? 'help' : status;
    try {
      final r = await rpc('push_location', {
        'p_bus': widget.bus, 'p_key': widget.busKey,
        'p_lat': f?.lat, 'p_lng': f?.lng, 'p_speed': f?.speed ?? 0, 'p_heading': f?.head, 'p_accuracy': f?.acc,
        'p_status': st,
      });
      final ok = r == true;
      if (!ok && netOk != false && running) say('ಸಿಗ್ನಲ್ ಇಲ್ಲ', 'No signal');
      netOk = ok;
      if (ok) lastSent = DateTime.now();
    } catch (_) {
      if (netOk != false && running) say('ಸಿಗ್ನಲ್ ಇಲ್ಲ', 'No signal');
      netOk = false;
    }
    sending = false;
    if (mounted) setState(() {});
    if (queued != null) { final q = queued!; queued = null; send(q); }
  }

  Future<void> setRun(bool on) async {
    running = on; fastCount = 0; stillSince = null;
    (await SharedPreferences.getInstance()).setBool('tripOn', on);
    if (on) { say('ಪ್ರಯಾಣ ಶುರುವಾಗಿದೆ', 'Trip started'); lastSent = DateTime.fromMillisecondsSinceEpoch(0); send('running'); }
    else { say('ಪ್ರಯಾಣ ಮುಗಿದಿದೆ', 'Trip ended'); send('off'); }
    if (mounted) setState(() {});
  }

  Future<void> sos() async {
    say('ಸಹಾಯಕ್ಕೆ ಕರೆ ಮಾಡಲಾಗುತ್ತಿದೆ', 'Calling for help');
    helpUntil = DateTime.now().add(const Duration(minutes: 10));
    lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    send('help');
    if (phone != null && phone!.isNotEmpty) await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  bool get gpsOk => last != null && DateTime.now().difference(last!.t).inSeconds < 30;

  @override
  Widget build(BuildContext context) {
    final problem = !svcOn || !precise;
    final bad = running && (!gpsOk || netOk == false);
    final bg = problem || bad ? cRed : running ? cGreen : cGrey;
    final no = RegExp(r'\d+').firstMatch(widget.bus)?.group(0) ?? widget.bus;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 16),
          // long-press the bus number for 3 s to unlink the phone (admin only)
          GestureDetector(
            onLongPress: () => showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Unlink this phone?'),
                content: const Text('Only the transport in-charge should do this.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('No')),
                  TextButton(onPressed: () { Navigator.pop(c); sub?.cancel(); widget.onUnlink(); }, child: const Text('Unlink')),
                ],
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.directions_bus, size: 64, color: Colors.white),
              const SizedBox(width: 12),
              Text(no, style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dot(last == null ? null : gpsOk, Icons.gps_fixed),
            const SizedBox(width: 24),
            _dot(netOk, Icons.signal_cellular_alt),
          ]),
          if (problem)
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: cRed, minimumSize: const Size(220, 64)),
                onPressed: () async { await Geolocator.openLocationSettings(); },
                icon: const Icon(Icons.location_off, size: 36),
                label: const Text('GPS', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ),
            ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 300, height: 300,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: running ? cBtnStop : cBtnGo,
                    shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 10)),
                    elevation: 10,
                  ),
                  onPressed: () => setRun(!running),
                  child: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 170, color: Colors.white),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: cRed, minimumSize: const Size(240, 80), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: sos,
              icon: const Icon(Icons.phone_in_talk, size: 44),
              label: const Text('SOS', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            ),
          ),
          Text(dbg, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Widget _dot(bool? ok, IconData ic) => Container(
        width: 52, height: 52,
        decoration: BoxDecoration(shape: BoxShape.circle, color: ok == null ? Colors.white24 : ok ? const Color(0xFF7CFC9A) : const Color(0xFFFF6B6B)),
        child: Icon(ic, color: Colors.black87),
      );
}
