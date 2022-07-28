import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:realtime_client/src/constants.dart';
import 'package:realtime_client/src/message.dart';
import 'package:realtime_client/src/realtime_channel.dart';
import 'package:realtime_client/src/realtime_subscription.dart';
import 'package:realtime_client/src/retry_timer.dart';
import 'package:realtime_client/src/websocket/websocket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WebSocketTransport = WebSocketChannel Function(
  String url,
  Map<String, String> headers,
);

typedef RealtimeEncode = void Function(
  dynamic payload,
  void Function(String result) callback,
);

typedef RealtimeDecode = void Function(
  String payload,
  void Function(dynamic result) callback,
);

class RealtimeClient {
  String? accessToken;
  List<dynamic> channels = [];
  final String endPoint;
  final Map<String, String> headers;
  final Map<String, String> params;
  final Duration timeout;
  final WebSocketTransport transport;
  int heartbeatIntervalMs = 30000;
  int longpollerTimeout = 20000;
  Timer? heartbeatTimer;
  String? pendingHeartbeatRef;
  int ref = 0;
  late RetryTimer reconnectTimer;

  void Function(String? kind, String? msg, dynamic data)? logger;
  late RealtimeEncode encode;
  late RealtimeDecode decode;
  late TimerCalculation reconnectAfterMs;

  WebSocketChannel? conn;
  List sendBuffer = [];
  Map<String, List<Function>> stateChangeCallbacks = {
    'open': [],
    'close': [],
    'error': [],
    'message': []
  };
  SocketStates? connState;

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
    WebSocketTransport? transport,
    RealtimeEncode? encode,
    RealtimeDecode? decode,
    this.timeout = Constants.defaultTimeout,
    this.heartbeatIntervalMs = 30000,
    this.longpollerTimeout = 20000,
    TimerCalculation? reconnectAfterMs,
    this.logger,
    this.params = const {},
    Map<String, String>? headers,
  })  : endPoint = '$endPoint/${Transports.websocket}',
        headers = {
          ...Constants.defaultHeaders,
          if (headers != null) ...headers,
        },
        transport = transport ?? createWebSocketClient {
    this.reconnectAfterMs =
        reconnectAfterMs ?? RetryTimer.createRetryFunction();
    this.encode = encode ??
        (dynamic payload, Function(String result) callback) =>
            callback(json.encode(payload));
    this.decode = decode ??
        (String payload, Function(dynamic result) callback) =>
            callback(json.decode(payload));
    reconnectTimer = RetryTimer(
      () async {
        await disconnect();
        connect();
      },
      this.reconnectAfterMs,
    );
  }

  /// Connects the socket.
  void connect() {
    if (conn != null) return;

    try {
      connState = SocketStates.connecting;
      conn = transport(endPointURL, headers);
      connState = SocketStates.open;

      _onConnOpen();
      conn!.stream.timeout(Duration(milliseconds: longpollerTimeout));
      conn!.stream.listen(
        // incoming messages
        (message) => onConnMessage(message as String),
        onError: _onConnError,
        onDone: () {
          // communication has been closed
          if (connState != SocketStates.disconnected) {
            connState = SocketStates.closed;
          }
          _onConnClose('');
        },
      );
    } catch (e) {
      /// General error handling
      _onConnError(e);
    }
  }

  /// Disconnects the socket with status [code] and [reason] for the disconnect
  Future<void> disconnect({int? code, String? reason}) async {
    final conn = this.conn;
    if (conn != null) {
      connState = SocketStates.disconnected;
      if (code != null) {
        await conn.sink.close(code, reason ?? '');
      } else {
        await conn.sink.close();
      }
      this.conn = null;
    }
  }

  /// Logs the message. Override `this.logger` for specialized logging.
  void log([String? kind, String? msg, dynamic data]) {
    logger?.call(kind, msg, data);
  }

  /// Registers callbacks for connection state change events
  ///
  /// Examples
  /// socket.onOpen(() {print("Socket opened.");});
  ///
  void onOpen(void Function() callback) {
    stateChangeCallbacks['open']!.add(callback);
  }

  /// Registers a callbacks for connection state change events.
  void onClose(void Function(dynamic) callback) {
    stateChangeCallbacks['close']!.add(callback);
  }

  /// Registers a callbacks for connection state change events.
  void onError(void Function(dynamic) callback) {
    stateChangeCallbacks['error']!.add(callback);
  }

  /// Calls a function any time a message is received.
  void onMessage(void Function(dynamic) callback) {
    stateChangeCallbacks['message']!.add(callback);
  }

  /// Returns the current state of the socket.
  String get connectionState {
    switch (connState) {
      case SocketStates.connecting:
        return 'connecting';
      case SocketStates.open:
        return 'open';
      case SocketStates.closing:
        return 'closing';
      case SocketStates.disconnected:
        return 'disconnected';
      case SocketStates.closed:
      default:
        return 'closed';
    }
  }

  /// Retuns `true` is the connection is open.
  bool get isConnected => connectionState == 'open';

  /// Removes a subscription from the socket.
  void remove(dynamic channel) {
    channels = channels.where((c) => c.joinRef != channel.joinRef).toList();
  }

  dynamic channel(
    String topic, {
    Map<String, dynamic> chanParams = const {},
  }) {
    final selfBroadcast = chanParams['selfBroadcast'] as bool?;
    chanParams.remove('selfBroadcast');
    final params = chanParams;

    if (selfBroadcast == true) {
      params['self_broadcast'] = selfBroadcast;
    }

    final chan = this.params['vsndate'] != null
        ? RealtimeChannel(topic, this, params)
        : RealtimeSubscription(topic, this, params);

    if (chan is RealtimeChannel) {
      chan.presence.onJoin((key, currentPresences, newPresences) {
        chan.trigger('presence', {
          'event': 'JOIN',
          'key': key,
          'currentPresences': currentPresences,
          'newPresences': newPresences,
        });
      });

      chan.presence.onLeave((key, currentPresences, leftPresences) {
        chan.trigger('presence', {
          'event': 'LEAVE',
          'key': key,
          'currentPresences': currentPresences,
          'leftPresences': leftPresences,
        });
      });

      chan.presence.onSync(() {
        chan.trigger('presence', {'event': 'SYNC'});
      });
    }

    channels.add(chan);
    return chan;
  }

  /// Push out a message if the socket is connected.
  ///
  /// If the socket is not connected, the message gets enqueued within a local buffer, and sent out when a connection is next established.
  void push(Message data) {
    void callback() {
      encode(data.toJson(), (result) {
        conn?.sink.add(result);
      });
    }

    log(
      'push',
      '${data.topic} ${data.event} (${data.ref})',
      data.payload,
    );

    if (isConnected) {
      callback();
    } else {
      sendBuffer.add(callback);
    }
  }

  void onConnMessage(String rawMessage) {
    decode(rawMessage, (msg) {
      final topic = msg['topic'] as String;
      final event = msg['event'] as String;
      final payload = msg['payload'];
      final ref = msg['ref'] as String?;
      if ((ref != null && ref == pendingHeartbeatRef) ||
          event == payload?.type) {
        pendingHeartbeatRef = null;
      }

      log(
        'receive',
        "${payload['status'] ?? ''} $topic $event ${ref != null ? '($ref)' : ''}",
        payload,
      );

      channels.where((channel) => channel.isMember(topic)).forEach(
            (channel) => channel.trigger(
              event,
              payload: payload,
              ref: ref,
            ),
          );
      for (final callback in stateChangeCallbacks['message']!) {
        callback(msg);
      }
    });
  }

  /// Returns the URL of the websocket.
  String get endPointURL {
    final params = Map<String, String>.from(this.params);
    params['vsn'] = Constants.vsn;
    return _appendParams(endPoint, params);
  }

  /// Return the next message ref, accounting for overflows
  String makeRef() {
    final int newRef = ref + 1;
    if (newRef < 0) {
      ref = 0;
    } else {
      ref = newRef;
    }
    return ref.toString();
  }

  /// Sets the JWT access token used for channel subscription authorization and Realtime RLS.
  ///
  /// `token` A JWT strings.
  void setAuth(String? token) {
    accessToken = token;

    for (final channel in channels) {
      if (token != null) {
        channel.updateJoinPayload({'user_token': token});
      }
      if (channel.joinedOnce && channel.isJoined) {
        channel.push(ChannelEvents.access_token, {'access_token': token ?? ''});
      }
    }
  }

  /// Unsubscribe from channels with the specified topic.
  void leaveOpenTopic(String topic) {
    try {
      final dupChannel = channels.firstWhere(
        (c) => c.topic == topic && (c.isJoined || c.isJoining),
      );

      log('transport', 'leaving duplicate topic "$topic"');
      dupChannel.unsubscribe();

      // ignore: avoid_catching_errors
    } on StateError {
      // state error is thrown when the channel is not found, so it's safe to do
      // nothing here
      return;
    }
  }

  void _onConnOpen() {
    log('transport', 'connected to $endPointURL');
    _flushSendBuffer();
    reconnectTimer.reset();
    if (heartbeatTimer != null) heartbeatTimer!.cancel();
    heartbeatTimer = Timer.periodic(
      Duration(milliseconds: heartbeatIntervalMs),
      (Timer t) => sendHeartbeat(),
    );
    for (final callback in stateChangeCallbacks['open']!) {
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
      reconnectTimer.scheduleTimeout();
    }
    if (heartbeatTimer != null) heartbeatTimer!.cancel();
    for (final callback in stateChangeCallbacks['close']!) {
      callback(event);
    }
  }

  void _onConnError(dynamic error) {
    log('transport', error.toString());
    _triggerChanError();
    for (final callback in stateChangeCallbacks['error']!) {
      callback(error);
    }
  }

  void _triggerChanError() {
    for (final channel in channels) {
      channel.trigger(ChannelEvents.error.name);
    }
  }

  String _appendParams(String url, Map<String, String> params) {
    if (params.keys.isEmpty) return url;

    var endpoint = Uri.parse(url);
    final searchParams = Map<String, dynamic>.from(endpoint.queryParameters);
    params.forEach((k, v) => searchParams[k] = v);
    endpoint = endpoint.replace(queryParameters: searchParams);

    return endpoint.toString();
  }

  void _flushSendBuffer() {
    if (isConnected && sendBuffer.isNotEmpty) {
      for (final callback in sendBuffer) {
        callback();
      }
      sendBuffer = [];
    }
  }

  void sendHeartbeat() {
    if (!isConnected) return;

    if (pendingHeartbeatRef != null) {
      pendingHeartbeatRef = null;
      log(
        'transport',
        'heartbeat timeout. Attempting to re-establish connection',
      );
      conn?.sink.close(Constants.wsCloseNormal, 'heartbeat timeout');
      return;
    }

    pendingHeartbeatRef = makeRef();
    push(
      Message(
        topic: 'phoenix',
        event: ChannelEvents.heartbeat,
        payload: {},
        ref: pendingHeartbeatRef,
      ),
    );
    setAuth(accessToken);
  }
}
