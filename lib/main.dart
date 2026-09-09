import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'services/subscription_service.dart';

const defaultSubscription = 'https://orginal.iranlightspeed.xyz:2096/sub/Amirali🎀';
final FlutterSingBox singBox = FlutterSingBox();
final ProfileStorage profileStorage = ProfileStorage();
final SubscriptionService subscriptionService = SubscriptionService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await singBox.init(); } catch (e) { debugPrint('sing-box init: $e'); }
  runApp(const LightSpeedApp());
}

class LightSpeedApp extends StatelessWidget {
  const LightSpeedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Light speed 🔥',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: Colors.deepPurple),
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
  List<Profile> profiles = [];
  Profile? selected;
  SubscriptionResult? subscription;
  bool running = false;
  bool busy = false;
  String status = 'آماده اتصال';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _refreshSubscription(silent: true);
  }

  void _loadProfiles() {
    profiles = profileStorage.getProfiles();
    selected = profileStorage.getSelectedProfile();
    if (mounted) setState(() {});
  }

  Future<void> _refreshSubscription({bool silent = false}) async {
    if (!silent) setState(() { busy = true; status = 'در حال دریافت اشتراک...'; });
    try {
      final result = await subscriptionService.fetch(urlController.text.trim());
      if (!mounted) return;
      setState(() { subscription = result; status = '${result.nodes.length} سرور دریافت شد'; });
    } catch (e) {
      if (!silent && mounted) _snack('دریافت اشتراک ناموفق بود: $e');
      if (mounted && !silent) setState(() => status = 'خطا در دریافت اشتراک');
    } finally {
      if (!silent && mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    final raw = urlController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _snack('لینک اشتراک معتبر نیست');
      return;
    }
    setState(() { busy = true; status = 'در حال افزودن اشتراک...'; });
    try {
      final profile = await ProfileService().importProfile(
        subscribeLink: uri,
        name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
        autoUpdateInterval: 86400,
      );
      profileStorage.setSelectedProfile(profile.id);
      _loadProfiles();
      await _refreshSubscription(silent: true);
      if (mounted) { setState(() => status = 'اشتراک آماده اتصال است'); _snack('اشتراک با موفقیت اضافه شد'); }
    } catch (e) {
      if (mounted) { setState(() => status = 'افزودن اشتراک ناموفق بود'); _snack('خطای اشتراک: $e'); }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleVpn() async {
    if (selected == null) { _snack('ابتدا اشتراک را اضافه کنید'); return; }
    setState(() => busy = true);
    try {
      if (running) {
        await singBox.stopVpn();
        if (mounted) setState(() { running = false; status = 'VPN قطع شد'; });
      } else {
        profileStorage.setSelectedProfile(selected!.id);
        await singBox.startVpn();
        if (mounted) setState(() { running = true; status = 'VPN متصل شد'; });
      }
    } catch (e) {
      if (mounted) { setState(() => status = 'اتصال ناموفق بود'); _snack('خطای VPN: $e'); }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _test() async {
    if (selected == null) return;
    setState(() => busy = true);
    try { await singBox.urlTest(groupTag: 'proxy'); _snack('تست سرورها انجام شد'); }
    catch (e) { _snack('تست سرورها انجام نشد: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void _select(Profile profile) {
    if (running) return;
    profileStorage.setSelectedProfile(profile.id);
    _loadProfiles();
  }

  void _delete(Profile profile) {
    if (running) return;
    profileStorage.deleteProfile(profile.id);
    _loadProfiles();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _bytes(int? value) {
    if (value == null) return 'نامشخص';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double n = value.toDouble();
    var i = 0;
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
    return '${n.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _expire(int? timestamp) {
    if (timestamp == null || timestamp <= 0) return 'نامشخص';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final info = subscription?.info;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Light speed 🔥'),
        centerTitle: true,
        actions: [IconButton(onPressed: busy ? null : () => _refreshSubscription(), icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            Icon(running ? Icons.shield : Icons.shield_outlined, size: 64),
            const SizedBox(height: 8),
            Text(running ? 'متصل' : 'قطع', style: Theme.of(context).textTheme.headlineSmall),
            Text(status),
            const SizedBox(height: 18),
            SizedBox(width: 150, height: 150, child: FilledButton(
              onPressed: busy ? null : _toggleVpn,
              style: FilledButton.styleFrom(shape: const CircleBorder()),
              child: Icon(running ? Icons.stop : Icons.power_settings_new, size: 56),
            )),
          ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Text('📊 اطلاعات اشتراک', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _info('آپلود', _bytes(info?.upload))), Expanded(child: _info('دانلود', _bytes(info?.download)))]),
            Row(children: [Expanded(child: _info('مصرف', _bytes(info?.used))), Expanded(child: _info('باقی‌مانده', _bytes(info?.remaining)))]),
            _info('حجم کل', _bytes(info?.total)),
            _info('انقضا', _expire(info?.expire)),
          ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'نام اشتراک', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: urlController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Subscription URL', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: busy ? null : _import, icon: const Icon(Icons.download), label: const Text('افزودن / بروزرسانی'))),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: busy ? null : _test, icon: const Icon(Icons.speed)),
            ]),
          ]))),
          const SizedBox(height: 16),
          Text('سرورها (${subscription?.nodes.length ?? 0})', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (subscription?.nodes.isEmpty ?? true)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('هنوز سروری از اشتراک خوانده نشده است.'))),
          ...?subscription?.nodes.asMap().entries.map((entry) => Card(child: ListTile(
            leading: CircleAvatar(child: Text('${entry.key + 1}')),
            title: Text(_nodeTitle(entry.value), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(entry.value, maxLines: 2, overflow: TextOverflow.ellipsis),
          ))),
          const SizedBox(height: 16),
          Text('پروفایل‌ها', style: Theme.of(context).textTheme.titleLarge),
          ...profiles.map((profile) => Card(child: ListTile(
            leading: Radio<int>(value: profile.id, groupValue: selected?.id, onChanged: running ? null : (_) => _select(profile)),
            title: Text(profile.name),
            trailing: IconButton(onPressed: running ? null : () => _delete(profile), icon: const Icon(Icons.delete_outline)),
            onTap: () => _select(profile),
          ))),
        ],
      ),
    );
  }

  Widget _info(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
  );

  String _nodeTitle(String node) {
    final hash = node.indexOf('#');
    if (hash >= 0 && hash + 1 < node.length) return Uri.decodeComponent(node.substring(hash + 1));
    final scheme = node.indexOf('://');
    return scheme > 0 ? node.substring(0, scheme).toUpperCase() : 'SERVER';
  }

  @override
  void dispose() {
    urlController.dispose();
    nameController.dispose();
    super.dispose();
  }
}
