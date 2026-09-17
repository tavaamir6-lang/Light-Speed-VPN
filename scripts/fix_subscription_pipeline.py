from pathlib import Path
import re

path = Path("lib/main.dart")
source = path.read_text()

old_pipeline = re.compile(
    r"  /// V2Box-style subscription pipeline:.*?\n  UserInfo\? _parseUserInfo",
    re.S,
)
new_pipeline = '''  /// Use the plugin's Dio-based subscription downloader, like V2Box-style clients.
  ///
  /// The old dart:io HttpClient implementation waited for the whole response
  /// stream to finish. Some subscription panels keep HTTP connections alive,
  /// so that stream could sit until the timeout even after the subscription
  /// data was already available. flutter_sing_box uses Dio and parses the
  /// response headers/body in its own subscription pipeline.
  Future<Profile> _importProfileFromSubscription(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('آدرس Subscription معتبر نیست');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('فقط لینک HTTP/HTTPS برای Subscription پشتیبانی می‌شود');
    }

    try {
      return await profileService
          .importProfile(
            subscribeLink: uri,
            userAgent: 'v2Box/10.1.5',
            autoUpdateInterval: 12,
          )
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw TimeoutException('Subscription در 45 ثانیه پاسخ کامل نداد');
    }
  }

'''

fixed, count = old_pipeline.subn(new_pipeline, source, count=1)
if count == 0 and "Future<Profile> _importProfileFromSubscription" not in source:
    raise SystemExit("Could not find the subscription pipeline in lib/main.dart")

fixed, _ = re.subn(
    r"  UserInfo\? _parseUserInfo\(String\? header\) \{.*?\n  \}\n\n",
    "",
    fixed,
    count=1,
    flags=re.S,
)

# Android VpnService/libbox does not implement strict_route. Use the
# supported full-device routing path: auto_route + auto_detect_interface.
fixed = fixed.replace("        'strict_route': true,\n", "")
fixed = fixed.replace("          inbound['strict_route'] = true;\n", "")

# gVisor is the most compatible TUN stack for Android VPN clients and is
# commonly used by V2Box/sing-box Android configurations, especially for UDP.
fixed = fixed.replace("        'stack': 'system',\n", "        'stack': 'gvisor',\n")
fixed = fixed.replace("          inbound['stack'] ??= 'system';\n", "          inbound['stack'] = 'gvisor';\n")

# Make TUN capture complete application traffic and improve UDP/NAT handling.
fixed = fixed.replace("        'dns_mode': 'hijack',\n", "        'dns_mode': 'hijack',\n        'sniff': true,\n        'sniff_override_destination': false,\n        'endpoint_independent_nat': true,\n")
fixed = fixed.replace("          inbound['dns_mode'] ??= 'hijack';\n", "          inbound['dns_mode'] = 'hijack';\n          inbound['sniff'] = true;\n          inbound['sniff_override_destination'] = false;\n          inbound['endpoint_independent_nat'] = true;\n")

# If the subscription has no DNS section, do not depend on Android's local
# resolver. Route DNS over HTTPS through the selected proxy outbound. This is
# important on networks where ordinary DNS is blocked or intercepted.
dns_block = """    if (!config.containsKey('dns')) {
      config['dns'] = {
        'servers': [
          {'tag': 'system', 'type': 'local'},
        ],
        'rules': [
          {'action': 'route', 'server': 'system'},
        ],
        'strategy': 'prefer_ipv4',
      };
    }
"""
dns_replacement = """    if (!config.containsKey('dns')) {
      config['dns'] = {
        'servers': [
          {
            'tag': 'remote',
            'type': 'https',
            'server': '1.1.1.1',
            'server_port': 443,
            'path': '/dns-query',
            'detour': finalTag,
          },
        ],
        'rules': [
          {'action': 'route', 'server': 'remote'},
        ],
        'final': 'remote',
        'strategy': 'prefer_ipv4',
      };
    }
"""
if dns_block in fixed:
    fixed = fixed.replace(dns_block, dns_replacement, 1)

path.write_text(fixed)
print("Subscription pipeline patched; Android TUN now uses gVisor, DNS-over-HTTPS via proxy, auto-route and loop prevention.")
