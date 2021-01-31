import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants.dart';
import 'message.dart';
import 'realtime_subscription.dart';
import 'retry_timer.dart';

typedef Logger = void Function(String kind, String msg, dynamic data);
typedef Encoder = void Function(
    dynamic payload, void Function(String result) callback);
typedef Decoder = void Function(
    String payload, void Function(dynamic result) callback);
typedef WebSocketChannelProvider = WebSocketChannel Function(
    String url, Map<String, String> headers);

class RealtimeClient {
  List<RealtimeSubscription> channels = [];
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
  Map<String, List<Function>> stateChangeCallbacks = {
    'open': [],
    'close': [],
    'error': [],
    'message': []
  };
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
  /// `reconnectAfterMs` The optional function that returns the millsec reconnect interval. Defaults to stepped backoff off.
  RealtimeClient(
    String endPoint, {
    WebSocketChannelProvider transport,
    this.encode,
    this.decode,
    this.timeout = Constants.defaultTimeout,
    this.heartbeatIntervalMs = 30000,
    this.longpollerTimeout = 20000,
    int Function(int) reconnectAfterMs,
    this.logger,
    this.params = const {},
    this.headers = const {},
  })  : endPoint = '$endPoint/${Transports.websocket}',
        transport = (transport ??
            (url, headers) =>
                IOWebSocketChannel.connect(url, headers: headers)) {
    this.reconnectAfterMs = reconnectAfterMs ??
        (int tries) {
          return [1000, 2000, 5000, 10000][tries - 1] ?? 10000;
        };
    encode ??= (dynamic payload, Function(String result) callback) =>
        callback(json.encode(payload));
    decode ??= (String payload, Function(dynamic result) callback) =>
        callback(json.decode(payload));

    reconnectTimer = RetryTimer(
        () => {disconnect(callback: () => connect())}, this.reconnectAfterMs);
  }

  /// Connects the socket.
  void connect() {
    if (conn != null) return;

    try {
      connState = SocketStates.connecting;
      conn = transport(endPointURL(), headers);
      if (conn != null) {
        connState = SocketStates.open;
        _onConnOpen();
        conn.stream.timeout(Duration(milliseconds: longpollerTimeout));
        conn.stream.listen((message) {
          // handling of the incoming messages
          onConnMessage(message as String);
        }, onError: (error) {
          // error handling
          _onConnError(error);
        }, onDone: () {
          // communication has been closed
          if (connState != SocketStates.disconnected) {
            connState = SocketStates.closed;
          }
          _onConnClose('');
        });
      }
    } catch (e) {
      /// General error handling
      _onConnError(e);
    }
  }

  /// Disconnects the socket with status [code] and [reason] for the disconnect
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

  /// Logs the message. Override `this.logger` for specialized logging.
  void log([String kind, String msg, dynamic data]) {
    if (logger != null) logger(kind, msg, data);
  }

  /// Registers callbacks for connection state change events
  ///
  /// Examples
  /// socket.onOpen(() {print("Socket opened.");});
  ///
  void onOpen(Function callback) {
    stateChangeCallbacks['open'].add(callback);
  }

  /// Registers a callbacks for connection state change events.
  void onClose(Function(dynamic) callback) {
    stateChangeCallbacks['close'].add(callback);
  }

  /// Registers a callbacks for connection state change events.
  void onError(Function(dynamic) callback) {
    stateChangeCallbacks['error'].add(callback);
  }

  /// Calls a function any time a message is received.
  void onMessage(Function(dynamic) callback) {
    stateChangeCallbacks['message'].add(callback);
  }

  /// Returns the current state of the socket.
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
        return 'closed';
    }
  }

  /// Retuns `true` is the connection is open.
  bool isConnected() {
    return connectionState() == 'open';
  }

  /// Removes a subscription from the socket.
  void remove(RealtimeSubscription channel) {
    channels = channels.where((c) => c.joinRef() != channel.joinRef()).toList();
  }

  RealtimeSubscription channel(String topic, {Map chanParams = const {}}) {
    final chan = RealtimeSubscription(topic, this, params: chanParams);
    channels.add(chan);
    return chan;
  }

  void push(Message message) {
    void callback() {
      encode(message.toJson(), (result) {
        // print('send message $result');
        conn.sink.add(result);
      });
    }

    log('push', '${message.topic} ${message.event} (${message.ref})', message.payload);

    if (isConnected()) {
      callback();
    } else {
      sendBuffer.add(callback);
    }
  }

  /// Returns the URL of the websocket.
  String endPointURL() {
    final params = Map<String, String>.from(this.params);
    params['vsn'] = Constants.vsn;
    return _appendParams(endPoint, params);
  }

  /// Return the next message ref, accounting for overflows
  String makeRef() {
    int newRef = ref + 1;
    if (newRef < 0) {
      newRef = 0;
    }
    ref = newRef;

    return ref.toString();
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

      log(
          'receive',
          "${payload['status'] ?? ''} $topic $event ${ref != null ? '($ref)' : ''}",
          payload);

      channels.where((channel) => channel.isMember(topic)).forEach(
          (channel) => channel.trigger(event, payload: payload, ref: ref));
      for (final callback in stateChangeCallbacks['message']) {
        callback(msg);
      }
    });
  }

  void sendHeartbeat() {
    if (!isConnected()) return;

    if (pendingHeartbeatRef != null) {
      pendingHeartbeatRef = null;
      log('transport',
          'heartbeat timeout. Attempting to re-establish connection');
      conn.sink.close(Constants.wsCloseNormal, 'heartbeat timeout');
      return;
    }

    pendingHeartbeatRef = makeRef();
    final message = Message(
        topic: 'phoenix',
        event: ChannelEvents.heartbeat,
        payload: {},
        ref: pendingHeartbeatRef);
    push(message);
  }

  void _onConnOpen() {
    log('transport', 'connected to ${endPointURL()}');
    _flushSendBuffer();
    reconnectTimer.reset();
    if (heartbeatTimer != null) heartbeatTimer.cancel();
    heartbeatTimer = Timer.periodic(Duration(milliseconds: heartbeatIntervalMs),
        (Timer t) => sendHeartbeat());
    for (final callback in stateChangeCallbacks['open']) {
      callback();
    }
  }

  /// communication has been closed
  void _onConnClose(String event) {
    log('transport', 'close', event);
    /// SocketStates.disconnected: by user with socket.disconnect()
    /// SocketStates.closed: NOT by user, should try to reconnect
    if (connState == SocketStates.closed) {
      _triggerChanError();
      if (heartbeatTimer != null) heartbeatTimer.cancel();
      reconnectTimer.scheduleTimeout();
    }
    for (final callback in stateChangeCallbacks['close']) {
      callback(event);
    }
  }

  void _onConnError(dynamic error) {
    log('transport', error.toString());
    _triggerChanError();
    for (final callback in stateChangeCallbacks['error']) {
      callback(error);
    }
  }

  void _triggerChanError() {
    for (final channel in channels) {
      channel.trigger(ChannelEvents.error.eventName());
    }
  }

  String _appendParams(String url, Map<String, dynamic> params) {
    if (params.keys.isEmpty) return url;

    var endpoint = Uri.parse(url);
    final searchParams = Map<String, dynamic>.from(endpoint.queryParameters);
    params.forEach((k, v) => searchParams[k] = v);
    endpoint = endpoint.replace(queryParameters: searchParams);

    return endpoint.toString();
  }

  void _flushSendBuffer() {
    if (isConnected() && sendBuffer.isNotEmpty) {
      for (final callback in sendBuffer) {
        callback();
      }
      sendBuffer = [];
    }
  }
}
