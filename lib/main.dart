import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'services/subscription_service.dart';

final FlutterSingBox singBox = FlutterSingBox();
final SubscriptionService subscriptions = SubscriptionService();
const defaultSubscription = 'https://orginal.iranlightspeed.xyz:2096/sub/Amirali🎀';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await singBox.init();
  } catch (e) {
    debugPrint('sing-box init failed: $e');
  }
  runApp(const LightSpeedApp());
}

class LightSpeedApp extends StatelessWidget {
  const LightSpeedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Light Speed VPN',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: Colors.blue),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final urlController = TextEditingController(text: defaultSubscription);
  final nameController = TextEditingController(text: 'Light Speed');
  StreamSubscription<ProxyState>? stateSubscription;
  List<Profile> profiles = [];
  Profile? selected;
  bool running = false;
  bool busy = false;
  String message = 'آماده اتصال';

  @override
  void initState() {
    super.initState();
    _reloadProfiles();
    stateSubscription = singBox.proxyStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        running = state == ProxyState.started;
        message = running ? 'VPN متصل است' : 'VPN قطع است';
      });
    });
  }

  void _reloadProfiles() {
    profiles = ProfileStorage().getProfiles();
    selected = ProfileStorage().getSelectedProfile();
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final raw = urlController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
      _snack('لینک اشتراک معتبر نیست');
      return;
    }
    setState(() { busy = true; message = 'در حال دریافت اشتراک...'; });
    try {
      final profile = await subscriptions.importSubscription(
        url: raw,
        name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
      );
      ProfileStorage().setSelectedProfile(profile.id);
      _reloadProfiles();
      _snack('اشتراک با موفقیت اضافه شد');
      if (mounted) setState(() => message = 'اشتراک آماده اتصال است');
    } catch (e) {
      _snack('خطای دریافت اشتراک: $e');
      if (mounted) setState(() => message = 'دریافت اشتراک ناموفق بود');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggle() async {
    if (selected == null) {
      _snack('ابتدا یک اشتراک اضافه و انتخاب کنید');
      return;
    }
    setState(() => busy = true);
    try {
      if (running) {
        await singBox.stopVpn();
        if (mounted) setState(() => message = 'در حال قطع VPN...');
      } else {
        ProfileStorage().setSelectedProfile(selected!.id);
        await singBox.startVpn();
        if (mounted) setState(() => message = 'درخواست اتصال ارسال شد');
      }
    } catch (e) {
      _snack('خطای VPN: $e');
      if (mounted) setState(() => message = 'اتصال ناموفق بود');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _test() async {
    if (selected == null) return;
    setState(() => busy = true);
    try {
      await singBox.urlTest(groupTag: 'proxy');
      _snack('تست تأخیر انجام شد');
    } catch (e) {
      _snack('تست سرورها در این اشتراک در دسترس نیست');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _select(Profile p) {
    if (running) return;
    ProfileStorage().setSelectedProfile(p.id);
    _reloadProfiles();
  }

  void _delete(Profile p) {
    if (running) return;
    ProfileStorage().deleteProfile(p.id);
    _reloadProfiles();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Light Speed VPN'), centerTitle: true,
        actions: [IconButton(onPressed: busy ? null : _import, icon: const Icon(Icons.sync))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Icon(running ? Icons.shield : Icons.shield_outlined, size: 64),
          const SizedBox(height: 8),
          Text(running ? 'متصل' : 'قطع', style: Theme.of(context).textTheme.headlineSmall),
          Text(message),
          const SizedBox(height: 18),
          SizedBox(width: 160, height: 160, child: FilledButton(
            onPressed: busy ? null : _toggle,
            style: FilledButton.styleFrom(shape: const CircleBorder()),
            child: Icon(running ? Icons.stop : Icons.power_settings_new, size: 58),
          )),
          if (selected != null) ...[
            const SizedBox(height: 14), Text(selected!.name, style: Theme.of(context).textTheme.titleLarge),
            Text('${selected!.outboundsCount} سرور'),
          ],
        ]))),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'نام اشتراک', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: urlController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Subscription URL', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: FilledButton.icon(onPressed: busy ? null : _import, icon: const Icon(Icons.download), label: Text(busy ? 'لطفاً صبر کنید...' : 'افزودن / بروزرسانی'))), const SizedBox(width: 8), IconButton.filledTonal(onPressed: selected == null || busy ? null : _test, icon: const Icon(Icons.speed))]),
        ]))),
        const SizedBox(height: 16),
        Text('اشتراک‌ها', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (profiles.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('اشتراکی ثبت نشده است'))),
        ...profiles.map((p) => Card(child: ListTile(
          leading: Radio<int>(value: p.id, groupValue: selected?.id, onChanged: running ? null : (_) => _select(p)),
          title: Text(p.name), subtitle: Text('${p.outboundsCount} سرور\n${p.typed.subscribeUrl ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis), isThreeLine: true,
          trailing: IconButton(onPressed: running ? null : () => _delete(p), icon: const Icon(Icons.delete_outline)), onTap: () => _select(p),
        ))),
      ]),
    );
  }

  @override
  void dispose() {
    stateSubscription?.cancel();
    urlController.dispose();
    nameController.dispose();
    super.dispose();
  }
}
