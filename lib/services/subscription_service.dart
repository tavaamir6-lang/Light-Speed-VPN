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
  int? get remaining => total == null || used == null ? null : (total! - used!).clamp(0, total!);

  factory SubscriptionInfo.fromHeaders(Map<String, String> headers) {
    final raw = headers['subscription-userinfo'] ?? headers['subscription-user-info'];
    if (raw == null || raw.trim().isEmpty) return const SubscriptionInfo();
    final values = <String, int>{};
    for (final part in raw.split(';')) {
      final p = part.trim();
      final i = p.indexOf('=');
      if (i <= 0) continue;
      final value = int.tryParse(p.substring(i + 1).trim());
      if (value != null) values[p.substring(0, i).trim().toLowerCase()] = value;
    }
    return SubscriptionInfo(
      upload: values['upload'],
      download: values['download'],
      total: values['total'],
      expire: values['expire'],
    );
  }
}

class SubscriptionResult {
  final String sourceUrl;
  final List<String> nodes;
  final SubscriptionInfo info;
  final String format;

  const SubscriptionResult({
    required this.sourceUrl,
    required this.nodes,
    required this.info,
    required this.format,
  });
}

class SubscriptionService {
  final ProfileService _profiles = ProfileService();

  Future<Profile> importSubscription({required String url, String? name}) async {
    final uri = _validUri(url);
    return _profiles.importProfile(
      subscribeLink: uri,
      name: name == null || name.trim().isEmpty ? null : name.trim(),
      autoUpdateInterval: 86400,
    );
  }

  Future<SubscriptionResult> fetch(String url) async {
    final uri = _validUri(url);
    final response = await http.get(uri, headers: const {
      'Accept': '*/*',
      'Cache-Control': 'no-cache',
      'User-Agent': 'LightSpeed/1.0',
    }).timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('HTTP ${response.statusCode}');
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trim();
    if (text.isEmpty) throw const FormatException('Subscription is empty');

    final parsed = parse(text);
    return SubscriptionResult(
      sourceUrl: url,
      nodes: parsed.nodes,
      info: SubscriptionInfo.fromHeaders(response.headers),
      format: parsed.format,
    );
  }

  static SubscriptionResult parse(String text) {
    var body = text.replaceFirst('\uFEFF', '').trim();
    var nodes = _extractLinks(body);
    if (nodes.isNotEmpty) {
      return SubscriptionResult(sourceUrl: '', nodes: nodes, info: const SubscriptionInfo(), format: 'URI list');
    }

    final decoded = _decodeBase64(body);
    if (decoded != null && decoded != body) {
      nodes = _extractLinks(decoded);
      if (nodes.isNotEmpty) {
        return SubscriptionResult(sourceUrl: '', nodes: nodes, info: const SubscriptionInfo(), format: 'Base64');
      }
      body = decoded.trim();
    }

    try {
      final value = jsonDecode(body);
      if (value is Map<String, dynamic>) {
        return SubscriptionResult(
          sourceUrl: '',
          nodes: _linksFromJson(value),
          info: const SubscriptionInfo(),
          format: 'JSON',
        );
      }
    } catch (_) {}

    return SubscriptionResult(
      sourceUrl: '',
      nodes: _extractLinks(body),
      info: const SubscriptionInfo(),
      format: 'Raw',
    );
  }

  static Uri _validUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid subscription URL');
    }
    return uri;
  }

  static String? _decodeBase64(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8) return null;
    try {
      return utf8.decode(base64.decode(base64.normalize(compact)));
    } catch (_) {
      return null;
    }
  }

  static List<String> _extractLinks(String body) {
    const schemes = {
      'vless', 'vmess', 'trojan', 'ss', 'ssr', 'hysteria', 'hysteria2',
      'hy2', 'tuic', 'wireguard', 'wg', 'socks', 'http', 'https', 'ssh',
    };
    final result = <String>[];
    final seen = <String>{};
    for (final raw in body.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      final match = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):\/\/', caseSensitive: false).firstMatch(line);
      if (match == null) continue;
      if (!schemes.contains(match.group(1)!.toLowerCase())) continue;
      if (seen.add(line)) result.add(line);
    }
    return result;
  }

  static List<String> _linksFromJson(Map<String, dynamic> json) {
    final outbounds = json['outbounds'];
    if (outbounds is! List) return const [];
    return outbounds.whereType<Map>().map((o) {
      final tag = o['tag'];
      final type = o['type'];
      if (tag == null || type == null) return null;
      return '$type — $tag';
    }).whereType<String>().toList();
  }
}
