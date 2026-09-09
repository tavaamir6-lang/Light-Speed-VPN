import 'dart:convert';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:http/http.dart' as http;

class SubscriptionInfo {
  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  const SubscriptionInfo({this.upload, this.download, this.total, this.expire});

  int? get used => upload == null || download == null ? null : upload! + download!;

  factory SubscriptionInfo.fromHeader(String? value) {
    if (value == null || value.trim().isEmpty) return const SubscriptionInfo();
    final map = <String, int>{};
    for (final part in value.split(';').map((e) => e.trim())) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final key = part.substring(0, i).trim().toLowerCase();
      final number = int.tryParse(part.substring(i + 1).trim());
      if (number != null) map[key] = number;
    }
    return SubscriptionInfo(
      upload: map['upload'],
      download: map['download'],
      total: map['total'],
      expire: map['expire'],
    );
  }
}

class SubscriptionResult {
  final String sourceUrl;
  final String body;
  final List<String> links;
  final SubscriptionInfo info;
  final String format;
  final Map<String, dynamic>? json;

  const SubscriptionResult({
    required this.sourceUrl,
    required this.body,
    required this.links,
    required this.info,
    required this.format,
    this.json,
  });

  int get nodeCount => links.length;
}

class SubscriptionService {
  final ProfileService _profiles = ProfileService();

  Future<Profile> importSubscription({required String url, String? name}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid subscription URL');
    }

    // Let flutter_sing_box handle the complete subscription natively.
    // This preserves UUID/password, TLS, Reality, WS/gRPC, DNS, routes,
    // proxy groups and all other fields instead of rebuilding lossy URLs.
    return _profiles.importProfile(
      subscribeLink: uri,
      name: name?.trim().isEmpty == true ? null : name?.trim(),
      autoUpdateInterval: 86400,
    );
  }

  Future<SubscriptionResult> fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid subscription URL');
    }

    final response = await http.get(uri, headers: const {
      'Accept': 'text/plain, text/yaml, application/json, application/yaml, */*',
      'User-Agent': 'Light-Speed-VPN/1.0',
    }).timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('Subscription HTTP ${response.statusCode}');
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trim();
    if (body.isEmpty) throw const FormatException('Subscription is empty');

    final info = SubscriptionInfo.fromHeader(
      response.headers['subscription-userinfo'] ??
          response.headers['subscription-user-info'],
    );
    final parsed = parse(body);
    return SubscriptionResult(
      sourceUrl: url,
      body: parsed.body,
      links: parsed.links,
      info: info,
      format: parsed.format,
      json: parsed.json,
    );
  }

  static SubscriptionResult parse(String input) {
    var body = input.replaceFirst('\uFEFF', '').trim();
    if (body.isEmpty) throw const FormatException('Subscription is empty');

    final direct = _extractLinks(body);
    if (direct.isNotEmpty) {
      return SubscriptionResult(
        sourceUrl: '',
        body: body,
        links: direct,
        info: const SubscriptionInfo(),
        format: 'uri-list',
      );
    }

    final decoded = _tryBase64(body);
    if (decoded != null && decoded.trim() != body) {
      final links = _extractLinks(decoded);
      if (links.isNotEmpty) {
        return SubscriptionResult(
          sourceUrl: '',
          body: decoded,
          links: links,
          info: const SubscriptionInfo(),
          format: 'base64',
        );
      }
      body = decoded.trim();
    }

    try {
      final value = jsonDecode(body);
      if (value is Map<String, dynamic>) {
        // Never flatten JSON outbounds into fake scheme://host:port URLs.
        // That would silently discard authentication and transport settings.
        final format = value.containsKey('outbounds')
            ? 'sing-box-json'
            : value.containsKey('proxies')
                ? 'clash-json'
                : 'json';
        return SubscriptionResult(
          sourceUrl: '',
          body: body,
          links: const <String>[],
          info: const SubscriptionInfo(),
          format: format,
          json: value,
        );
      }
    } catch (_) {
      // YAML or URI lists are handled below.
    }

    final yamlLinks = _extractLinks(body);
    return SubscriptionResult(
      sourceUrl: '',
      body: body,
      links: yamlLinks,
      info: const SubscriptionInfo(),
      format: yamlLinks.isNotEmpty ? 'uri-list' : 'raw',
    );
  }

  static String? _tryBase64(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8) return null;
    try {
      return utf8.decode(
        base64.decode(base64.normalize(compact)),
        allowMalformed: false,
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> _extractLinks(String body) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in body.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(
        r'^([A-Za-z][A-Za-z0-9+.-]*):\/\/',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;
      final scheme = match.group(1)!.toLowerCase();
      if (!_schemes.contains(scheme)) continue;
      if (seen.add(line)) result.add(line);
    }
    return result;
  }

  static const _schemes = <String>{
    'vless',
    'vmess',
    'trojan',
    'ss',
    'hysteria',
    'hysteria2',
    'hy2',
    'tuic',
    'wireguard',
    'wg',
    'socks',
    'http',
    'https',
    'ssh',
  };

  static List<String> decodeText(String body) => parse(body).links;
}
