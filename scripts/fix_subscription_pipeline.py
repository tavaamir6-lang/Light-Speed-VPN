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

# Remove the now-unused manual subscription-userinfo parser if it still exists.
fixed, _ = re.subn(
    r"  UserInfo\? _parseUserInfo\(String\? header\) \{.*?\n  \}\n\n",
    "",
    fixed,
    count=1,
    flags=re.S,
)

path.write_text(fixed)
print("Subscription pipeline patched successfully and unused parser removed.")
