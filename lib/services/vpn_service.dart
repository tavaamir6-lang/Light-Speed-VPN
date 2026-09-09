import 'dart:async';
import 'package:flutter_sing_box/flutter_sing_box.dart';

class VpnService {
  final FlutterSingBox client;
  Stream<ProxyState> get stateStream => client.proxyStateStream;

  VpnService(this.client);

  Future<void> initialize() => client.init();

  Future<void> start() => client.startVpn();

  Future<void> stop() => client.stopVpn();

  Future<void> test(String groupTag) => client.urlTest(groupTag: groupTag);
}
