import 'dart:io';

import 'package:test/test.dart';
import 'package:realtime_client/realtime_client.dart';
import 'package:web_socket_channel/io.dart';

typedef IOWebSocketChannelClosure = IOWebSocketChannel Function(
    String url, Map<String, String> headers);

void main() {
  HttpServer mockServer;

  setUp(() async {
    mockServer = await HttpServer.bind('localhost', 0);
    mockServer.transform(WebSocketTransformer()).listen((webSocket) {
      final channel = IOWebSocketChannel(webSocket);
      channel.stream.listen((request) {
        channel.sink.add(request);
      });
    });
  });

  tearDown(() async {
    if (mockServer != null) {
      await mockServer.close();
    }
  });

  group('constructor', () {
    test('sets defaults', () async {
      final socket = Socket('wss://example.com/socket');
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
      expect(socket.transport is IOWebSocketChannelClosure, true);
      expect(socket.timeout, const Duration(milliseconds: 10000));
      expect(socket.longpollerTimeout, 20000);
      expect(socket.heartbeatIntervalMs, 30000);
      expect(socket.logger is Logger, false);
      expect(socket.reconnectAfterMs is Function, true);
    });

    test('overrides some defaults with options', () async {
      final socket = Socket('wss://example.com/socket',
          timeout: const Duration(milliseconds: 40000),
          longpollerTimeout: 50000,
          heartbeatIntervalMs: 60000,
          logger: (kind, msg, data) => {});
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
      expect(socket.transport is IOWebSocketChannelClosure, true);
      expect(socket.timeout, const Duration(milliseconds: 40000));
      expect(socket.longpollerTimeout, 50000);
      expect(socket.heartbeatIntervalMs, 60000);
      expect(socket.logger is Logger, true);
      expect(socket.reconnectAfterMs is Function, true);
    });
  });

  group('endpointURL', () {
    test('returns endpoint for given full url', () {
      final socket = Socket('wss://example.org/chat');
      expect(
        socket.endPointURL(),
        'wss://example.org/chat/websocket?vsn=1.0.0',
      );
    });

    test('returns endpoint with parameters', () {
      final socket = Socket('ws://example.org/chat', params: {'foo': 'bar'});
      expect(socket.endPointURL(),
          'ws://example.org/chat/websocket?foo=bar&vsn=1.0.0');
    });

    test('returns endpoint with apikey', () {
      final socket =
          Socket('ws://example.org/chat', params: {'apikey': '123456789'});
      expect(socket.endPointURL(),
          'ws://example.org/chat/websocket?apikey=123456789&vsn=1.0.0');
    });
  });

  group('connect with Websocket', () {
    Socket socket;

    setUp(() {
      socket = Socket('ws://localhost:${mockServer.port}');
    });

    test('establishes websocket connection with endpoint', () {
      socket.connect();

      final conn = socket.conn;

      expect(conn, isA<IOWebSocketChannel>());
      //! Not verifying connection url
    });

    test('sets callbacks for connection', () async {
      int opens = 0;
      socket.onOpen(() {
        opens += 1;
      });
      int closes = 0;
      socket.onClose((_) {
        closes += 1;
      });
      dynamic lastMsg;
      socket.onMessage((m) {
        lastMsg = m;
      });

      socket.connect();
      expect(opens, 1);

      socket.sendHeartbeat();
      // need to wait for event to trigger
      await Future.delayed(const Duration(seconds: 1), () {});
      expect(lastMsg['event'], 'phx_heartbeat');

      socket.disconnect();
      await Future.delayed(const Duration(seconds: 1), () {});
      expect(closes, 1);
    });

    test('sets callback for errors', () {
      dynamic lastErr;
      final erroneousSocket = Socket('badurl')
        ..onError((e) {
          lastErr = e;
        });

      erroneousSocket.connect();

      expect(lastErr, isA<WebSocketException>());
    });

    test('is idempotent', () {
      socket.connect();
      final conn = socket.conn;
      socket.connect();
      expect(socket.conn, conn);
    });
  });

  group('disconnect', () {
    Socket socket;
    setUp(() {
      socket = Socket('wss://localhost:0/');
    });
    test('removes existing connection', () {
      socket.connect();
      socket.disconnect();

      expect(socket.conn, null);
    });

    test('calls callback', () {
      int closes = 0;
      socket.connect();
      socket.disconnect(callback: () {
        closes += 1;
      });

      expect(closes, 1);
    });
  });
}
