import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';

final FlutterSingBox singBox = FlutterSingBox();
const String defaultSubscription = 'https://orginal.iranlightspeed.xyz:2096/sub/Amirali🎀';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await singBox.init();
  runApp(const LightSpeedApp());
}

class LightSpeedApp extends StatelessWidget {
  const LightSpeedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Light Speed VPN',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _url = TextEditingController(text: defaultSubscription);
  final _name = TextEditingController(text: 'Light Speed');
  List<Profile> profiles = [];
  Profile? selected;
  bool running = false;
  bool loading = false;
  String status = 'قطع';
  StreamSubscription<ProxyState>? _statusSub;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _statusSub = singBox.proxyStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        running = state == ProxyState.started;
        status = running ? 'متصل' : 'قطع';
      });
    });
  }

  void _loadProfiles() {
    profiles = ProfileStorage().getProfiles();
    selected = ProfileStorage().getSelectedProfile();
    if (mounted) setState(() {});
  }

  Future<void> _addSubscription() async {
    final raw = _url.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _message('لینک اشتراک معتبر نیست');
      return;
    }
    setState(() => loading = true);
    try {
      final profile = await ProfileService().importProfile(
        subscribeLink: uri,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        autoUpdateInterval: 24 * 60 * 60,
      );
      ProfileStorage().setSelectedProfile(profile.id);
      _loadProfiles();
      _message('اشتراک با موفقیت دریافت شد');
    } catch (e) {
      _message('دریافت اشتراک ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _toggleVpn() async {
    if (selected == null) {
      _message('ابتدا اشتراک را اضافه کنید');
      return;
    }
    try {
      if (running) {
        await singBox.stopVpn();
      } else {
        ProfileStorage().setSelectedProfile(selected!.id);
        await singBox.startVpn();
      }
    } catch (e) {
      _message('خطای اتصال VPN: $e');
    }
  }

  Future<void> _testSelected() async {
    if (selected == null) return;
    try {
      await singBox.urlTest(groupTag: 'proxy');
      _message('تست سرور انجام شد');
    } catch (_) {
      _message('تست تأخیر برای این اشتراک در دسترس نیست');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Light Speed VPN'),
        actions: [
          IconButton(onPressed: _addSubscription, icon: const Icon(Icons.sync)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(running ? Icons.shield : Icons.shield_outlined, size: 56),
                const SizedBox(height: 8),
                Text(status, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                SizedBox(
                  width: 155, height: 155,
                  child: FilledButton(
                    onPressed: loading ? null : _toggleVpn,
                    child: Icon(running ? Icons.stop : Icons.power_settings_new, size: 58),
                  ),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 12),
                  Text(selected!.name, style: Theme.of(context).textTheme.titleMedium),
                  Text('${selected!.outboundsCount} سرور'),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام اشتراک', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Subscription URL', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: loading ? null : _addSubscription, icon: const Icon(Icons.add_link), label: Text(loading ? 'در حال دریافت...' : 'افزودن / بروزرسانی'))),
                  const SizedBox(width: 8),
                  IconButton(onPressed: selected == null ? null : _testSelected, icon: const Icon(Icons.speed), tooltip: 'تست سرعت'),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('اشتراک‌ها', style: Theme.of(context).textTheme.titleLarge)),
            Text('${profiles.length} مورد'),
          ]),
          const SizedBox(height: 8),
          if (profiles.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('هنوز اشتراکی اضافه نشده است')))),
          ...profiles.map((p) => Card(
            child: ListTile(
              leading: Radio<int>(value: p.id, groupValue: selected?.id, onChanged: (v) { if (v != null) { ProfileStorage().setSelectedProfile(v); _loadProfiles(); } }),
              title: Text(p.name),
              subtitle: Text('${p.outboundsCount} سرور\n${p.typed.subscribeUrl ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: running ? null : () { ProfileStorage().deleteProfile(p.id); _loadProfiles(); }),
              onTap: running ? null : () { ProfileStorage().setSelectedProfile(p.id); _loadProfiles(); },
            ),
          )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _url.dispose();
    _name.dispose();
    super.dispose();
  }
}
