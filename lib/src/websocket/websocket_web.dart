import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> createWebSocketClient(
  String url,
  Map<String, String> headers,
) async {
  return HtmlWebSocketChannel.connect(url);
}
