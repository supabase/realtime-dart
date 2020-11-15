import 'dart:convert';
import 'dart:io';

import 'package:mockito/mockito.dart';
import 'package:realtime_client/src/lib/constants.dart';
import 'package:test/test.dart';
import 'package:realtime_client/realtime_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'socket_test_stubs.dart';

typedef IOWebSocketChannelClosure = IOWebSocketChannel Function(
    String url, Map<String, String> headers);

void main() {
  const int int64MaxValue = 9223372036854775807;

  const socketEndpoint = 'wss://localhost:0/';

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
    } else {
      print('mock server was null');
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
          logger: (kind, msg, data) => print('[$kind] $msg $data'));
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
      Socket erroneousSocket = Socket('badurl')
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
      socket = Socket(socketEndpoint);
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

    test('calls connection close callback', () {
      final mockedSocketChannel = MockIOWebSocketChannel();
      final mockedSocket = Socket(
        socketEndpoint,
        transport: (url, headers) {
          return mockedSocketChannel;
        },
      );
      final mockedSink = MockWebSocketSink();

      when(mockedSocketChannel.sink).thenReturn(mockedSink);

      const tCode = 12;
      const tReason = 'reason';

      mockedSocket.connect();

      mockedSocket.disconnect(code: tCode, reason: tReason);

      verify(mockedSink.close(tCode, tReason));
    });

    test('does not throw when no connection', () {
      expect(() => socket.disconnect(), returnsNormally);
    });
  });

  //! Note: not checking connection states since it is based on an enum.

  group('channel', () {
    const tTopic = 'topic';
    const tParams = {'one': 'two'};
    Socket socket;
    setUp(() {
      socket = Socket(socketEndpoint);
    });

    test('returns channel with given topic and params', () {
      final channel = socket.channel(
        tTopic,
        chanParams: tParams,
      );

      expect(channel.socket, socket);
      expect(channel.topic, tTopic);
      expect(channel.params, tParams);
    });

    test('adds channel to sockets channels list', () {
      expect(socket.channels.length, 0);

      final channel = socket.channel(
        tTopic,
        chanParams: tParams,
      );

      expect(socket.channels.length, 1);

      final foundChannel = socket.channels[0];
      expect(foundChannel, channel);
    });
  });

  group('remove', () {
    test('removes given channel from channels', () {
      final mockedChannel1 = MockChannel();
      when(mockedChannel1.joinRef()).thenReturn('1');

      final mockedChannel2 = MockChannel();
      when(mockedChannel2.joinRef()).thenReturn('2');

      const tTopic1 = 'topic-1';
      const tTopic2 = 'topic-2';

      final mockedSocket = SocketWithMockedChannel(socketEndpoint);
      mockedSocket.mockedChannelLooker.addAll(<String, Channel>{
        tTopic1: mockedChannel1,
        tTopic2: mockedChannel2,
      });

      final channel1 = mockedSocket.channel(tTopic1);
      final channel2 = mockedSocket.channel(tTopic2);

      mockedSocket.remove(channel1);
      expect(mockedSocket.channels.length, 1);

      final foundChannel = mockedSocket.channels[0];
      expect(foundChannel, channel2);
    });
  });

  group('push', () {
    const topic = 'topic';
    const event = ChannelEvents.join;
    const payload = 'payload';
    const ref = 'ref';
    final jsonData = json.encode({
      'topic': topic,
      'event': event.eventName(),
      'payload': payload,
      'ref': ref
    });

    IOWebSocketChannel mockedSocketChannel;
    Socket mockedSocket;
    WebSocketSink mockedSink;

    setUp(() {
      mockedSocketChannel = MockIOWebSocketChannel();
      mockedSocket = Socket(
        socketEndpoint,
        transport: (url, headers) {
          return mockedSocketChannel;
        },
      );
      mockedSink = MockWebSocketSink();

      when(mockedSocketChannel.sink).thenReturn(mockedSink);
    });

    test('sends data to connection when connected', () {
      mockedSocket.connect();
      mockedSocket.connState = SocketStates.open;

      mockedSocket.push(topic: topic, payload: payload, event: event, ref: ref);

      verify(mockedSink.add(jsonData));
    });

    test('buffers data when not connected', () {
      mockedSocket.connect();
      mockedSocket.connState = SocketStates.connecting;

      expect(mockedSocket.sendBuffer.length, 0);

      mockedSocket.push(topic: topic, payload: payload, event: event, ref: ref);

      verifyNever(mockedSink.add(jsonData));
      expect(mockedSocket.sendBuffer.length, 1);

      final callback = mockedSocket.sendBuffer[0];
      callback();
      verify(mockedSink.add(jsonData));
    });
  });

  group('makeRef', () {
    Socket socket;
    setUp(() {
      socket = Socket(socketEndpoint);
    });

    test('returns next message ref', () {
      expect(socket.ref, 0);
      expect(socket.makeRef(), '1');
      expect(socket.ref, 1);
      expect(socket.makeRef(), '2');
      expect(socket.ref, 2);
    });

    test('restarts for overflow', () {
      socket.ref = int64MaxValue + 1;
      expect(socket.makeRef(), '0');
      expect(socket.ref, 0);
    });
  });
}
