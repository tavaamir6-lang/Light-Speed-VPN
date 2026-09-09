import 'dart:convert';
import 'package:flutter_sing_box/flutter_sing_box.dart';

class SubscriptionService {
  final ProfileService _profiles = ProfileService();

  Future<Profile> importSubscription({
    required String url,
    String? name,
  }) async {
    final uri = Uri.parse(url.trim());
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw FormatException('Invalid subscription URL');
    }
    return _profiles.importProfile(
      subscribeLink: uri,
      name: name?.trim().isEmpty == true ? null : name?.trim(),
      autoUpdateInterval: 86400,
    );
  }

  static List<String> decodeText(String body) {
    final text = body.trim();
    if (text.isEmpty) return const [];
    final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    final direct = lines.where((e) => RegExp(r'^(vless|vmess|trojan|ss|hysteria2?|tuic|wireguard)://', caseSensitive: false).hasMatch(e)).toList();
    if (direct.isNotEmpty) return direct;
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      return decoded.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return lines.toList();
    }
  }
}
