import 'package:flutter_test/flutter_test.dart';
import 'package:light_speed_vpn/main.dart';

void main() {
  testWidgets('Light speed app starts', (tester) async {
    await tester.pumpWidget(const LightSpeedApp());
    expect(find.text('Light speed 🔥'), findsOneWidget);
    expect(find.text('لینک Subscription را وارد کن'), findsOneWidget);
  });
}
