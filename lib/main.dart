import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'services/subscription_service.dart';

final FlutterSingBox singBox = FlutterSingBox();
final SubscriptionService subscriptions = SubscriptionService();
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
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark,
        ),
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
  String lastAction = 'آماده';
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
    setState(() {
      loading = true;
      lastAction = 'در حال دریافت و تحلیل اشتراک...';
    });
    try {
      final profile = await subscriptions.importSubscription(
        url: raw,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      );
      ProfileStorage().setSelectedProfile(profile.id);
      _loadProfiles();
      _message('اشتراک با موفقیت دریافت و ذخیره شد');
      if (mounted) setState(() => lastAction = 'اشتراک بروزرسانی شد');
    } catch (e) {
      _message('دریافت اشتراک ناموفق بود: $e');
      if (mounted) setState(() => lastAction = 'خطا در دریافت اشتراک');
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
        if (mounted) setState(() => lastAction = 'VPN متوقف شد');
      } else {
        ProfileStorage().setSelectedProfile(selected!.id);
        await singBox.startVpn();
        if (mounted) setState(() => lastAction = 'درخواست اتصال ارسال شد');
      }
    } catch (e) {
      _message('خطای اتصال VPN: $e');
    }
  }

  Future<void> _testSelected() async {
    if (selected == null) return;
    try {
      setState(() => loading = true);
      await singBox.urlTest(groupTag: 'proxy');
      _message('تست سرور انجام شد');
      if (mounted) setState(() => lastAction = 'تست تأخیر انجام شد');
    } catch (_) {
      _message('تست تأخیر برای این اشتراک در دسترس نیست');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _select(Profile profile) {
    if (running) return;
    ProfileStorage().setSelectedProfile(profile.id);
    _loadProfiles();
  }

  void _delete(Profile profile) {
    if (running) return;
    ProfileStorage().deleteProfile(profile.id);
    _loadProfiles();
    _message('اشتراک حذف شد');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Light Speed VPN'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: loading ? null : _addSubscription,
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'بروزرسانی اشتراک',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _addSubscription,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                      ),
                      child: Icon(
                        running ? Icons.shield_rounded : Icons.shield_outlined,
                        size: 46,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(status, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(lastAction, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: FilledButton(
                        onPressed: loading ? null : _toggleVpn,
                        style: FilledButton.styleFrom(shape: const CircleBorder()),
                        child: Icon(
                          running ? Icons.stop_rounded : Icons.power_settings_new_rounded,
                          size: 58,
                        ),
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 16),
                      Text(selected!.name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('${selected!.outboundsCount} سرور در اشتراک'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('اشتراک جدید', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'نام اشتراک',
                        prefixIcon: Icon(Icons.label_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Subscription URL',
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: loading ? null : _addSubscription,
                            icon: const Icon(Icons.download_rounded),
                            label: Text(loading ? 'در حال دریافت...' : 'افزودن / بروزرسانی'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: selected == null || loading ? null : _testSelected,
                          icon: const Icon(Icons.speed_rounded),
                          tooltip: 'تست سرورها',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('اشتراک‌ها', style: Theme.of(context).textTheme.titleLarge)),
                Chip(label: Text('${profiles.length} مورد')),
              ],
            ),
            const SizedBox(height: 8),
            if (profiles.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Center(child: Text('هنوز اشتراکی اضافه نشده است')),
                ),
              ),
            ...profiles.map(
              (p) => Card(
                child: ListTile(
                  leading: Radio<int>(
                    value: p.id,
                    groupValue: selected?.id,
                    onChanged: running ? null : (v) { if (v != null) _select(p); },
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.outboundsCount} سرور\n${p.typed.subscribeUrl ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: running ? null : () => _delete(p),
                  ),
                  onTap: () => _select(p),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اشتراک هر ۲۴ ساعت به‌صورت خودکار برای دریافت کانفیگ‌های جدید بروزرسانی می‌شود.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
