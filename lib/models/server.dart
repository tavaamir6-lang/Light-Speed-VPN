class Server {
  final String tag;
  final String type;
  final String? address;
  final int? port;
  final int? delay;

  const Server({
    required this.tag,
    required this.type,
    this.address,
    this.port,
    this.delay,
  });

  factory Server.fromMap(Map<String, dynamic> map) => Server(
        tag: '${map['tag'] ?? 'Server'}',
        type: '${map['type'] ?? 'unknown'}',
        address: map['server']?.toString(),
        port: map['server_port'] is int ? map['server_port'] as int : int.tryParse('${map['server_port'] ?? ''}'),
      );
}
