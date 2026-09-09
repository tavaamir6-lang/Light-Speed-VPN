import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';

final FlutterSingBox singBox = FlutterSingBox();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await singBox.init();
  runApp(const LightSpeedApp());
}

class LightSpeedApp extends StatelessWidget {
  const LightSpeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Light Speed VPN',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  List<Profile> profiles = [];
  Profile? selected;
  bool running = false;
  String status = 'قطع';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    singBox.proxyStateStream.listen((state) {
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
    setState(() {});
  }

  Future<void> _addSubscription() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _message('لینک اشتراک معتبر نیست');
      return;
    }
    try {
      final profile = await ProfileService().importProfile(
        subscribeLink: uri,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      );
      ProfileStorage().setSelectedProfile(profile.id);
      _url.clear();
      _name.clear();
      _loadProfiles();
      _message('کانفیگ با موفقیت اضافه شد');
    } catch (e) {
      _message('خطا در دریافت کانفیگ: $e');
    }
  }

  Future<void> _toggleVpn() async {
    if (selected == null) {
      _message('ابتدا یک کانفیگ اضافه و انتخاب کنید');
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
      _message('خطای VPN: $e');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Light Speed VPN')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(status, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                SizedBox(
                  width: 150,
                  height: 150,
                  child: FilledButton(
                    onPressed: _toggleVpn,
                    child: Icon(running ? Icons.stop : Icons.power_settings_new, size: 58),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام کانفیگ', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'لینک Subscription', hintText: 'https://...', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _addSubscription, icon: const Icon(Icons.add_link), label: const Text('افزودن کانفیگ')),
          const SizedBox(height: 16),
          Text('کانفیگ‌ها', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...profiles.map((p) => Card(
            child: ListTile(
              leading: Radio<int>(value: p.id, groupValue: selected?.id, onChanged: (v) { if (v != null) { ProfileStorage().setSelectedProfile(v); _loadProfiles(); } }),
              title: Text(p.name),
              subtitle: Text(p.typed.subscribeUrl ?? ''),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { ProfileStorage().deleteProfile(p.id); _loadProfiles(); }),
              onTap: () { ProfileStorage().setSelectedProfile(p.id); _loadProfiles(); },
            ),
          )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }
}
