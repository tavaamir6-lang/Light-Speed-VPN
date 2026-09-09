import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LightSpeedApp());

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

  ServerConfig({required this.raw, required this.type, required this.address, required this.port});
}

class SubscriptionInfo {
  final int upload;
  final int download;
  final int total;
  final int expire;

  const SubscriptionInfo({this.upload = 0, this.download = 0, this.total = 0, this.expire = 0});

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
  List<ServerConfig> configs = [];
  SubscriptionInfo? subscription;
  bool loading = false;
  bool testing = false;
  String status = 'لینک Subscription را وارد کن';

  @override
  void initState() {
    super.initState();
    _restoreUrl();
  }

  Future<void> _restoreUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('subscription_url');
    if (value != null && value.isNotEmpty) {
      urlController.text = value;
      await loadSubscription();
    }
  }

  Future<void> loadSubscription() async {
    final url = urlController.text.trim();
    if (url.isEmpty) {
      setState(() => status = 'لینک Subscription را وارد کن');
      return;
    }
    setState(() {
      loading = true;
      status = 'در حال دریافت Subscription...';
    });
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'LightSpeed/1.0',
        'Accept': '*/*',
        'Cache-Control': 'no-cache',
      }).timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final info = _parseUserInfo(response.headers['subscription-userinfo']);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      final decoded = _decodeSubscription(text);
      final parsed = _parseConfigs(decoded);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('subscription_url', url);
      if (!mounted) return;
      setState(() {
        subscription = info;
        configs = parsed;
        status = parsed.isEmpty ? 'کانفیگی پیدا نشد' : '${parsed.length} سرور پیدا شد';
        loading = false;
      });
      if (parsed.isNotEmpty) await testPings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        status = 'خطا در دریافت Subscription: $e';
      });
    }
  }

  SubscriptionInfo? _parseUserInfo(String? value) {
    if (value == null || value.isEmpty) return null;
    final map = <String, int>{};
    for (final part in value.split(';')) {
      final pair = part.trim().split('=');
      if (pair.length == 2) map[pair[0]] = int.tryParse(pair[1]) ?? 0;
    }
    return SubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: map['expire'] ?? 0,
    );
  }

  String _decodeSubscription(String input) {
    final direct = input.trim();
    if (RegExp(r'(?m)^(vless|vmess|trojan|ss|ssr|hysteria2?|hy2|hy|tuic|wireguard)://').hasMatch(direct)) {
      return direct;
    }
    String current = direct;
    for (int i = 0; i < 3; i++) {
      try {
        var normalized = current.replaceAll('-', '+').replaceAll('_', '/');
        normalized += '=' * ((4 - normalized.length % 4) % 4);
        final bytes = base64.decode(normalized);
        final next = utf8.decode(bytes, allowMalformed: true).trim();
        if (next.isEmpty || next == current) break;
        current = next;
      } catch (_) {
        break;
      }
    }
    return current;
  }

  List<ServerConfig> _parseConfigs(String text) {
    final result = <ServerConfig>[];
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final uri = Uri.tryParse(line);
      if (uri == null || !line.contains('://')) continue;
      final type = uri.scheme.toLowerCase();
      const supported = {'vless', 'vmess', 'trojan', 'ss', 'ssr', 'hysteria', 'hysteria2', 'hy2', 'hy', 'tuic', 'wireguard'};
      if (!supported.contains(type)) continue;
      final port = uri.hasPort ? uri.port : 443;
      final host = uri.host.isNotEmpty ? uri.host : _hostFromRaw(line);
      if (host.isEmpty) continue;
      result.add(ServerConfig(raw: line, type: type, address: host, port: port));
    }
    return result;
  }

  String _hostFromRaw(String raw) {
    try {
      final rest = raw.split('://').last;
      final authority = rest.split('/').first.split('@').last;
      return authority.split(':').first;
    } catch (_) {
      return '';
    }
  }

  Future<void> testPings() async {
    if (configs.isEmpty) return;
    setState(() => testing = true);
    await Future.wait(configs.map((server) async {
      final watch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(server.address, server.port, timeout: const Duration(seconds: 3));
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

  String _bytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double n = bytes.toDouble();
    int i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _expire(int timestamp) {
    if (timestamp <= 0) return 'نامشخص';
    return DateFormat('yyyy/MM/dd').format(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Light speed 🔥', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: loading ? null : loadSubscription, icon: const Icon(Icons.refresh))],
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
                suffixIcon: IconButton(icon: const Icon(Icons.download), onPressed: loading ? null : loadSubscription),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 12),
            Text(status, textAlign: TextAlign.center),
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
                  if (testing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📊 اطلاعات اشتراک', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: info.progress, minHeight: 8, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 12),
          Text('مصرف: ${_bytes(info.used)} / ${_bytes(info.total)}'),
          Text('آپلود: ${_bytes(info.upload)}'),
          Text('دانلود: ${_bytes(info.download)}'),
          Text('باقی‌مانده: ${_bytes(info.remaining)}'),
          Text('انقضا: ${_expire(info.expire)}'),
        ]),
      ),
    );
  }

  Widget _serverCard(int index, ServerConfig server) {
    final fastest = index == 1 && server.ping != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Text('$index')),
        title: Text(server.raw.split('#').last.replaceAll(RegExp(r'^[^#]*#'), '').trim().isEmpty ? server.type.toUpperCase() : server.raw.split('#').last), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${server.type.toUpperCase()} • ${server.address}:${server.port}'),
        trailing: fastest ? Text('⚡ ${server.ping} ms', style: const TextStyle(fontWeight: FontWeight.bold)) : Text(server.ping == null ? '—' : '${server.ping} ms'),
      ),
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }
}
