import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:intl/intl.dart';
import 'package:mmkv/mmkv.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterSingBox vpn = FlutterSingBox();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize();
  try {
    await vpn.init();
  } catch (e) {
    debugPrint('VPN core init failed: $e');
  }
  runApp(const LightSpeedApp());
}

class LightSpeedApp extends StatelessWidget {
  const LightSpeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Light speed 🔥',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const HomePage(),
    );
  }
}

class ServerConfig {
  final String raw;
  final String type;
  final String address;
  final int port;
  int? ping;

  ServerConfig({
    required this.raw,
    required this.type,
    required this.address,
    required this.port,
    this.ping,
  });
}

class SubscriptionInfo {
  final int upload;
  final int download;
  final int total;
  final int expire;

  const SubscriptionInfo({
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire = 0,
  });

  int get used => upload + download;
  int get remaining => total > used ? total - used : 0;
  double get progress => total <= 0 ? 0 : (used / total).clamp(0, 1).toDouble();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final urlController = TextEditingController();
  final ProfileService profileService = ProfileService();
  final ProfileStorage profileStorage = ProfileStorage();

  StreamSubscription<List<ClientGroup>>? groupSubscription;
  List<ClientGroup> groups = [];
  List<ServerConfig> configs = [];
  SubscriptionInfo? subscription;
  Profile? importedProfile;

  bool loading = false;
  bool testing = false;
  bool connecting = false;
  bool connected = false;
  bool autoConnect = true;
  String status = 'لینک Subscription را وارد کن';
  String coreVersion = 'sing-box';
  String? activeOutbound;

  @override
  void initState() {
    super.initState();
    groupSubscription = vpn.groupStream.listen((value) {
      groups = value;
      if (mounted) {
        _syncConfigsFromGroupsIfNeeded();
        setState(() {});
      }
    });
    _loadCoreVersion();
    _restoreUrl();
  }

  Future<void> _loadCoreVersion() async {
    try {
      final version = await vpn.getSingBoxVersion();
      if (mounted) setState(() => coreVersion = 'sing-box $version');
    } catch (_) {}
  }

  Future<void> _restoreUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('subscription_url');
    if (value != null && value.isNotEmpty) {
      urlController.text = value;
      await loadSubscription();
    }
  }

  /// New subscription architecture:
  /// 1) Do NOT download the subscription with a separate Flutter http client.
  /// 2) Let flutter_sing_box/ProfileService handle the remote subscription.
  /// 3) Read the normalized local sing-box JSON produced by the plugin.
  /// 4) Use the native sing-box groups/url-test for server selection.
  /// This is the important difference from the old implementation: a 30s
  /// Flutter HTTP timeout can no longer prevent the native profile importer
  /// from reading the subscription.
  Future<void> loadSubscription({bool autoConnectAfterLoad = true}) async {
    final url = urlController.text.trim();
    if (url.isEmpty) {
      if (mounted) setState(() => status = 'لینک Subscription را وارد کن');
      return;
    }

    if (loading) return;

    setState(() {
      loading = true;
      status = 'در حال خواندن Subscription با sing-box...';
    });

    try {
      final profile = await _importProfile();
      importedProfile = profile;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('subscription_url', url);

      subscription = _subscriptionInfoFromProfile(profile);
      configs = await _readServersFromProfile(profile);

      // The native group stream can arrive just after importProfile returns.
      await _waitForNativeGroups();
      _syncConfigsFromGroupsIfNeeded();

      if (!mounted) return;
      setState(() {
        loading = false;
        status = configs.isEmpty
            ? 'Subscription خوانده شد ولی سروری پیدا نشد'
            : '${configs.length} سرور خوانده شد';
      });

      if (autoConnectAfterLoad && autoConnect && !connected && configs.isNotEmpty) {
        await connectBestServer();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        connecting = false;
        status = 'خطا در خواندن Subscription: $e';
      });
    }
  }

  Future<Profile?> _importProfile() async {
    final url = urlController.text.trim();
    if (url.isEmpty) throw Exception('Subscription URL خالی است');

    // ProfileService uses the plugin's NetworkService/Dio stack instead of
    // the old raw http.get() path. It also handles remote profile parsing,
    // Base64 subscriptions and normalization into sing-box configuration.
    return profileService.importProfile(
      subscribeLink: Uri.parse(url),
      userAgent: 'LightSpeed/1.0',
      autoUpdateInterval: 12,
    );
  }

  SubscriptionInfo? _subscriptionInfoFromProfile(Profile profile) {
    try {
      final dynamic info = profile.userInfo;
      if (info == null) return null;

      final dynamic raw = info.toJson();
      if (raw is! Map) return null;

      int value(String key) => int.tryParse('${raw[key] ?? 0}') ?? 0;
      return SubscriptionInfo(
        upload: value('upload'),
        download: value('download'),
        total: value('total'),
        expire: value('expire'),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ServerConfig>> _readServersFromProfile(Profile profile) async {
    try {
      final file = File(profile.typed.path);
      if (!await file.exists()) return [];

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final rawOutbounds = decoded['outbounds'];
      if (rawOutbounds is! List) return [];

      const nodeTypes = {
        'vless',
        'vmess',
        'trojan',
        'shadowsocks',
        'ss',
        'hysteria',
        'hysteria2',
        'tuic',
        'wireguard',
        'ssh',
        'naive',
      };

      final result = <ServerConfig>[];
      for (final item in rawOutbounds) {
        if (item is! Map) continue;

        final type = '${item['type'] ?? ''}'.toLowerCase();
        final address = '${item['server'] ?? ''}'.trim();
        if (!nodeTypes.contains(type) || address.isEmpty) continue;

        final port = int.tryParse('${item['server_port'] ?? 443}') ?? 443;
        final tag = '${item['tag'] ?? type}'.trim();
        result.add(ServerConfig(
          raw: tag,
          type: type,
          address: address,
          port: port,
        ));
      }

      return result;
    } catch (e) {
      debugPrint('Reading normalized profile failed: $e');
      return [];
    }
  }

  Future<void> _waitForNativeGroups() async {
    for (var i = 0; i < 25; i++) {
      if (groups.any((group) => group.items?.isNotEmpty == true)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void _syncConfigsFromGroupsIfNeeded() {
    if (configs.isNotEmpty || groups.isEmpty) return;

    final result = <ServerConfig>[];
    for (final group in groups) {
      final items = group.items;
      if (items == null) continue;
      for (final item in items) {
        result.add(ServerConfig(
          raw: item.tag,
          type: item.type,
          address: item.tag,
          port: 0,
          ping: item.urlTestDelay > 0 ? item.urlTestDelay : null,
        ));
      }
    }
    configs = result;
  }

  Future<void> testPings() async {
    if (configs.isEmpty || testing) return;
    setState(() => testing = true);

    // This is only a lightweight reachability indicator for the UI.
    // Actual proxy quality is measured by native sing-box urlTest after VPN
    // startup, which is what is used for the real fastest-server decision.
    await Future.wait(configs.map((server) async {
      if (server.port <= 0) return;
      final watch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(
          server.address,
          server.port,
          timeout: const Duration(seconds: 3),
        );
        await socket.close();
        server.ping = watch.elapsedMilliseconds;
      } catch (_) {
        server.ping = null;
      }
    }));

    configs.sort((a, b) => (a.ping ?? 999999).compareTo(b.ping ?? 999999));
    if (!mounted) return;
    setState(() => testing = false);
  }

  Future<void> _runNativeUrlTests() async {
    final currentGroups = List<ClientGroup>.from(groups);
    for (final group in currentGroups) {
      if (group.items == null || group.items!.isEmpty) continue;
      if (!group.selectable && group.type != 'urltest') continue;
      try {
        await vpn.urlTest(groupTag: group.tag);
      } catch (e) {
        debugPrint('urlTest ${group.tag} failed: $e');
      }
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  Future<void> _selectFastestNativeOutbound() async {
    ClientGroup? bestGroup;
    ClientGroupItem? bestItem;

    for (final group in groups) {
      final items = group.items;
      if (items == null || items.isEmpty || !group.selectable) continue;
      for (final item in items) {
        final delay = item.urlTestDelay;
        if (delay <= 0) continue;
        if (bestItem == null || delay < bestItem.urlTestDelay) {
          bestGroup = group;
          bestItem = item;
        }
      }
    }

    if (bestGroup == null || bestItem == null) return;

    await vpn.selectOutbound(
      groupTag: bestGroup.tag,
      outboundTag: bestItem.tag,
    );
    activeOutbound = bestItem.tag;

    if (mounted) {
      setState(() {
        status = 'متصل • سریع‌ترین: ${bestItem!.tag} (${bestItem.urlTestDelay} ms)';
      });
    }
  }

  Future<void> connectBestServer() async {
    if (connecting || connected) return;

    if (importedProfile == null || configs.isEmpty) {
      await loadSubscription(autoConnectAfterLoad: false);
      if (importedProfile == null || configs.isEmpty) return;
    }

    setState(() {
      connecting = true;
      status = 'در حال اتصال با سریع‌ترین سرور...';
    });

    try {
      final profile = importedProfile!;
      final source = File(profile.typed.path);
      if (!await source.exists()) {
        importedProfile = null;
        throw Exception('فایل پروفایل محلی پیدا نشد');
      }

      final target = await profileStorage.getUsingConfig();
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      profileStorage.setSelectedProfile(profile.id);

      await vpn.startVpn();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _runNativeUrlTests();
      await _selectFastestNativeOutbound();

      if (!mounted) return;
      setState(() {
        connected = true;
        connecting = false;
        if (activeOutbound == null) {
          status = 'VPN فعال است';
        }
      });
    } catch (e) {
      try {
        await vpn.stopVpn();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        connecting = false;
        connected = false;
        activeOutbound = null;
        status = 'خطای اتصال: $e';
      });
    }
  }

  Future<void> disconnectVpn() async {
    try {
      await vpn.stopVpn();
    } catch (e) {
      if (mounted) setState(() => status = 'خطای قطع اتصال: $e');
      return;
    }
    if (mounted) {
      setState(() {
        connected = false;
        activeOutbound = null;
        status = 'اتصال قطع شد';
      });
    }
  }

  String _bytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double n = bytes.toDouble();
    var i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _expire(int timestamp) {
    if (timestamp <= 0) return 'نامشخص';
    return DateFormat('yyyy/MM/dd').format(
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Light speed 🔥', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: loading ? null : loadSubscription,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadSubscription,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Subscription URL',
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: loading ? null : loadSubscription,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اتصال خودکار به سریع‌ترین سرور'),
              value: autoConnect,
              onChanged: connected ? null : (value) => setState(() => autoConnect = value),
            ),
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(coreVersion, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: connecting ? null : (connected ? disconnectVpn : connectBestServer),
              icon: Icon(connected ? Icons.stop_circle : Icons.power_settings_new),
              label: Text(connected ? 'قطع VPN' : 'اتصال به سریع‌ترین سرور'),
            ),
            if (subscription != null) ...[
              const SizedBox(height: 16),
              _trafficCard(subscription!),
            ],
            const SizedBox(height: 16),
            if (configs.isNotEmpty)
              Row(
                children: [
                  const Text('سرورها', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (testing)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  IconButton(onPressed: testing ? null : testPings, icon: const Icon(Icons.speed)),
                ],
              ),
            ...configs.asMap().entries.map((entry) => _serverCard(entry.key + 1, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _trafficCard(SubscriptionInfo info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📊 اطلاعات اشتراک', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: info.progress, minHeight: 8, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 12),
            Text('مصرف: ${_bytes(info.used)} / ${_bytes(info.total)}'),
            Text('آپلود: ${_bytes(info.upload)}'),
            Text('دانلود: ${_bytes(info.download)}'),
            Text('باقی‌مانده: ${_bytes(info.remaining)}'),
            Text('انقضا: ${_expire(info.expire)}'),
          ],
        ),
      ),
    );
  }

  Widget _serverCard(int index, ServerConfig server) {
    final fastest = index == 1 && server.ping != null;
    final name = server.raw.isNotEmpty ? server.raw : server.type.toUpperCase();
    final endpoint = server.port > 0 ? '${server.address}:${server.port}' : server.address;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Text('$index')),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${server.type.toUpperCase()} • $endpoint', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: fastest
            ? Text('⚡ ${server.ping} ms', style: const TextStyle(fontWeight: FontWeight.bold))
            : Text(server.ping == null ? '—' : '${server.ping} ms'),
      ),
    );
  }

  @override
  void dispose() {
    groupSubscription?.cancel();
    urlController.dispose();
    super.dispose();
  }
}
