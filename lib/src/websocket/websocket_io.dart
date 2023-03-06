import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> createWebSocketClient(
  String url,
  Map<String, String> headers,
) async {
  final ws = await WebSocket.connect(url, headers: headers);
  return IOWebSocketChannel(ws);
}
