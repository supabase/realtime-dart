import 'package:test/test.dart';
import 'package:realtime/client.dart';

import 'package:web_socket_channel/io.dart';

void main() {
  test('basic select table', () async {
    var socket = Socket('wss://example.com/socket');
    expect(socket.channels.length, 0);
    expect(socket.sendBuffer.length, 0);
    expect(socket.ref, 0);
    expect(socket.endPoint, 'wss://example.com/socket/websocket');
    expect(socket.stateChangeCallbacks, {
      'open': [],
      'close': [],
      'error': [],
      'message': [],
    });
    expect(socket.transport, IOWebSocketChannel);
    expect(socket.timeout, 10000);
    expect(socket.longpollerTimeout, 20000);
    expect(socket.heartbeatIntervalMs, 30000);
    expect(socket.logger is Function, true);
    expect(socket.reconnectAfterMs is Function, true);
  });
}
