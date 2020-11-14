import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'channel.dart';
import 'lib/constants.dart';
import 'lib/retry_timer.dart';

typedef Logger = void Function(String kind, String msg, dynamic data);
typedef Encoder = void Function(dynamic payload, void Function(String result) callback);
typedef Decoder = void Function(String payload, void Function(dynamic result) callback);
typedef WebSocketChannelProvider = WebSocketChannel Function(String url, Map<String, String> headers);

class Socket {
  List<Channel> channels = [];
  final String endPoint;
  final Map<String, String> headers;
  final Map<String, String> params;
  final Duration timeout;
  final WebSocketChannelProvider transport;
  int heartbeatIntervalMs = 30000;
  int longpollerTimeout = 20000;
  Timer heartbeatTimer;
  String pendingHeartbeatRef;
  int ref = 0;
  RetryTimer reconnectTimer;
  Logger logger;
  Encoder encode;
  Decoder decode;
  int Function(int) reconnectAfterMs;
  WebSocketChannel conn;
  List sendBuffer = [];
  Map<String, List<Function>> stateChangeCallbacks = {'open': [], 'close': [], 'error': [], 'message': []};
  SocketStates connState;

  /// Initializes the Socket
  ///
  /// `endPoint` The string WebSocket endpoint, ie, "ws://example.com/socket", "wss://example.com", "/socket" (inherited host & protocol)
  /// `transport` The Websocket Transport, for example WebSocket.
  /// `timeout` The default timeout in milliseconds to trigger push timeouts.
  /// `params` The optional params to pass when connecting.
  /// `headers` The optional headers to pass when connecting.
  /// `heartbeatIntervalMs` The millisec interval to send a heartbeat message.
  /// `logger` The optional function for specialized logging, ie: logger: (kind, msg, data) => { console.log(`$kind: $msg`, data) }
  /// `encode` The function to encode outgoing messages. Defaults to JSON: (payload, callback) => callback(JSON.stringify(payload))
  /// `decode` The function to decode incoming messages. Defaults to JSON: (payload, callback) => callback(JSON.parse(payload))
  /// `longpollerTimeout` The maximum timeout of a long poll AJAX request. Defaults to 20s (double the server long poll timer).
  /// `reconnectAfterMs` he optional function that returns the millsec reconnect interval. Defaults to stepped backoff off.
  Socket(
    String endPoint, {
    WebSocketChannelProvider transport,
    this.encode,
    this.decode,
    this.timeout = Constants.DEFAULT_TIMEOUT,
    this.heartbeatIntervalMs = 30000,
    this.longpollerTimeout = 20000,
    int Function(int) reconnectAfterMs,
    this.logger,
    this.params = const {},
    this.headers = const {},
  })  : endPoint = '$endPoint/${Transports.websocket}',
        transport = (transport ?? (url, headers) => IOWebSocketChannel.connect(url, headers: headers)) {
    this.reconnectAfterMs = reconnectAfterMs ??
        (int tries) {
          return [1000, 5000, 10000][tries - 1] ?? 10000;
        };
    encode ??= (dynamic payload, Function(String result) callback) => callback(json.encode(payload));
    decode ??= (String payload, Function(dynamic result) callback) => callback(json.decode(payload));

    reconnectTimer = RetryTimer(() => {disconnect(callback: () => connect())}, this.reconnectAfterMs);
  }

  String endPointURL() {
    final params = Map<String, String>.from(this.params);
    params['vsn'] = Constants.VSN;
    return appendParams(endPoint, params);
  }

  String appendParams(String url, Map<String, dynamic> params) {
    if (params.keys.isEmpty) return url;

    var endpoint = Uri.parse(url);
    final searchParams = Map<String, dynamic>.from(endpoint.queryParameters);
    params.forEach((k, v) => searchParams[k] = v);
    endpoint = endpoint.replace(queryParameters: searchParams);

    return endpoint.toString();
  }

  void disconnect({Function callback, int code, String reason}) {
    if (conn != null || conn?.sink != null) {
      connState = SocketStates.disconnected;
      if (code != null) {
        conn.sink.close(code, reason ?? '');
      } else {
        conn.sink.close();
      }
      conn = null;
    }
    if (callback != null) callback();
  }

  void connect() {
    if (conn != null) return;

    try {
      connState = SocketStates.connecting;
      conn = transport(endPointURL(), headers);
      if (conn != null) {
        connState = SocketStates.open;
        onConnOpen();
        conn.stream.timeout(Duration(milliseconds: longpollerTimeout));
        conn.stream.listen((message) {
          // handling of the incoming messages
          onConnMessage(message as String);
        }, onError: (error) {
          // error handling
          onConnError(error);
        }, onDone: () {
          // communication has been closed
          if (connState != SocketStates.disconnected) {
            connState = SocketStates.closed;
          }
          onConnClose('');
        });
      }
    } catch (e) {
      /// General error handling
      onConnError(e);
    }
  }

  /// Logs the message. Override `this.logger` for specialized logging.
  void log([String kind, String msg, dynamic data]) {
    if (logger != null) logger(kind, msg, data);
  }

  /// Registers callbacks for connection state change events
  ///
  /// Examples
  /// socket.onError(function(error){ alert("An error occurred") })
  ///
  void onOpen(Function callback) {
    stateChangeCallbacks['open'].add(callback);
  }

  void onClose(Function(dynamic) callback) {
    stateChangeCallbacks['close'].add(callback);
  }

  void onError(Function(dynamic) callback) {
    stateChangeCallbacks['error'].add(callback);
  }

  void onMessage(Function(dynamic) callback) {
    stateChangeCallbacks['message'].add(callback);
  }

  void onConnOpen() {
    log('transport', 'connected to ${endPointURL()}');
    flushSendBuffer();
    reconnectTimer.reset();
    if (heartbeatTimer != null) heartbeatTimer.cancel();
    heartbeatTimer = Timer.periodic(Duration(milliseconds: heartbeatIntervalMs), (Timer t) => sendHeartbeat());
    for (final callback in stateChangeCallbacks['open']) {
      callback();
    }
  }

  void onConnClose(String event) {
    log('transport', 'close', event);
    if (connState != SocketStates.disconnected) {
      triggerChanError();
      if (heartbeatTimer != null) heartbeatTimer.cancel();
      reconnectTimer.scheduleTimeout();
    }
    for (final callback in stateChangeCallbacks['close']) {
      callback(event);
    }
  }

  void onConnError(dynamic error) {
    log('transport', error.toString());
    triggerChanError();
    for (final callback in stateChangeCallbacks['error']) {
      callback(error);
    }
  }

  void triggerChanError() {
    for (final channel in channels) {
      channel.trigger(ChannelEvents.error.eventName());
    }
  }

  String connectionState() {
    switch (connState) {
      case SocketStates.connecting:
        return 'connecting';
      case SocketStates.open:
        return 'open';
      case SocketStates.closing:
        return 'closing';
      case SocketStates.closed:
        return 'closed';
      case SocketStates.disconnected:
        return 'disconnected';
      default:
        return '';
    }
  }

  bool isConnected() {
    return connectionState() == 'open';
  }

  void remove(Channel channel) {
    channels = channels.where((c) => c.joinRef() != channel.joinRef()).toList();
  }

  Channel channel(String topic, {Map chanParams = const {}}) {
    final chan = Channel(topic, this, params: chanParams);
    channels.add(chan);
    return chan;
  }

  void push({String topic, ChannelEvents event, dynamic payload, String ref}) {
    void callback() {
      encode({'topic': topic, 'event': event.eventName(), 'payload': payload, 'ref': ref}, (result) {
        // print('send message $result');
        conn.sink.add(result);
      });
    }
    log('push', '$topic $event ($ref)', payload);

    if (isConnected()) {
      callback();
    } else {
      sendBuffer.add(callback);
    }
  }

  // Return the next message ref, accounting for overflows
  String makeRef() {
    final newRef = ref + 1;
    if (newRef == ref) {
      ref = 0;
    } else {
      ref = newRef;
    }

    return ref.toString();
  }

  void sendHeartbeat() {
    if (!isConnected()) return;

    if (pendingHeartbeatRef != null) {
      pendingHeartbeatRef = null;
      log('transport', 'heartbeat timeout. Attempting to re-establish connection');
      conn.sink.close(Constants.WS_CLOSE_NORMAL, 'heartbeat timeout');
      return;
    }

    pendingHeartbeatRef = makeRef();
    push(topic: 'phoenix', event: ChannelEvents.heartbeat, payload: {}, ref: pendingHeartbeatRef);
  }

  void flushSendBuffer() {
    if (isConnected() && sendBuffer.isNotEmpty) {
      for (final callback in sendBuffer){
        callback();
      }
      sendBuffer = [];
    }
  }

  void onConnMessage(String rawMessage) {
    decode(rawMessage, (msg) {
      final topic = msg['topic'] as String;
      final event = msg['event'] as String;
      final payload = msg['payload'];
      final ref = msg['ref'] as String;
      if (ref != null && ref == pendingHeartbeatRef) {
        pendingHeartbeatRef = null;
      }

      log('receive', "${payload['status'] ?? ''} $topic $event ${ref != null ? '($ref)' : ''}", payload);

      channels
          .where((channel) => channel.isMember(topic))
          .forEach((channel) => channel.trigger(event, payload: payload, ref: ref));
      for (final callback in stateChangeCallbacks['message']) {
        callback(msg);
      }
    });
  }
}
