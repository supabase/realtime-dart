import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:web_socket_channel/io.dart';

import 'lib/constants.dart' as constants;
import 'channel.dart';
import 'lib/retry_timer.dart';

class Socket {
  List<Channel> channels = [];
  String endPoint = '';
  Map<String, String> headers = {};
  Map<String, String> params = {};
  int timeout = constants.DEFAULT_TIMEOUT;
  dynamic transport = IOWebSocketChannel;
  int heartbeatIntervalMs = 30000;
  int longpollerTimeout = 20000;
  Timer heartbeatTimer;
  String pendingHeartbeatRef;
  int ref = 0;
  RetryTimer reconnectTimer;
  Function logger;
  Function encode;
  Function decode;
  Function reconnectAfterMs;
  IOWebSocketChannel conn;
  List sendBuffer = [];
  Map<String, List<Function>> stateChangeCallbacks = {
    'open': [],
    'close': [],
    'error': [],
    'message': []
  };

  /// Initializes the Socket
  ///
  /// `endPoint` The string WebSocket endpoint, ie, "ws://example.com/socket", "wss://example.com", "/socket" (inherited host & protocol)
  /// `transport` The Websocket Transport, for example WebSocket.
  /// `timeout` The default timeout in milliseconds to trigger push timeouts.
  /// `params` The optional params to pass when connecting.
  /// `headers` The optional headers to pass when connecting.
  /// `heartbeatIntervalMs` The millisec interval to send a heartbeat message.
  /// `logger` The optional function for specialized logging, ie: logger: (kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }
  /// `encode` The function to encode outgoing messages. Defaults to JSON: (payload, callback) => callback(JSON.stringify(payload))
  /// `decode` The function to decode incoming messages. Defaults to JSON: (payload, callback) => callback(JSON.parse(payload))
  /// `longpollerTimeout` The maximum timeout of a long poll AJAX request. Defaults to 20s (double the server long poll timer).
  /// `reconnectAfterMs` he optional function that returns the millsec reconnect interval. Defaults to stepped backoff off.
  Socket(
    String endPoint, {
    dynamic transport = IOWebSocketChannel,
    Function encode,
    Function decode,
    int timeout = constants.DEFAULT_TIMEOUT,
    int heartbeatIntervalMs = 30000,
    int longpollerTimeout = 20000,
    Function reconnectAfterMs,
    Function logger,
    Map<String, String> params = const {},
    Map<String, String> headers = const {},
  }) {
    this.endPoint = '${endPoint}/${constants.TRANSPORTS.websocket}';
    this.params = params;
    this.headers = headers;
    this.timeout = timeout;
    this.logger = logger;
    this.transport = transport;
    this.heartbeatIntervalMs = heartbeatIntervalMs;
    this.longpollerTimeout = longpollerTimeout;
    this.reconnectAfterMs = reconnectAfterMs ??
        (int tries) {
          return [1000, 5000, 10000][tries - 1] ?? 10000;
        };
    this.encode = encode ??
        (dynamic payload, Function callback) => callback(json.encode(payload));
    this.decode = decode ??
        (dynamic payload, Function callback) => callback(json.decode(payload));

    reconnectTimer = RetryTimer(
        () => {disconnect(callback: () => connect())}, this.reconnectAfterMs);
  }

  String endPointURL() {
    var params = Map.from(this.params);
    params['vsn'] = constants.VSN;
    return appendParams(endPoint, params);
  }

  String appendParams(String url, Map params) {
    if (params.keys.isEmpty) return url;

    var endpoint = Uri.parse(url);
    var searchParams = Map<String, dynamic>.from(endpoint.queryParameters);
    params.forEach((k, v) => searchParams[k] = v);
    endpoint = endpoint.replace(queryParameters: searchParams);

    return endpoint.toString();
  }

  void disconnect({Function callback, int code, String reason}) {
    if (conn != null) {
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

    conn = IOWebSocketChannel.connect(endPointURL(), headers: headers);
    // TODO:
    // https://www.didierboelens.com/2018/06/web-sockets-build-a-real-time-game/
    // https://github.com/dart-lang/web_socket_channel/issues/16
    // if (conn != null) {
    //   // this.conn.timeout = this.longpollerTimeout // TYPE ERROR
    //   conn.onopen = () => this.onConnOpen()
    //   conn.onerror = (error) => this.onConnError(error)
    //   conn.onmessage = (event) => this.onConnMessage(event)
    //   conn.onclose = (event) => this.onConnClose(event)
    // }
  }

  /// Logs the message. Override `this.logger` for specialized logging. noops by default
  void log([String kind, String msg, dynamic data]) {
    logger(kind, msg, data);
  }

  /// Registers callbacks for connection state change events
  ///
  /// Examples
  /// socket.onError(function(error){ alert("An error occurred") })
  ///
  void onOpen(callback) {
    stateChangeCallbacks['open'].add(callback);
  }

  void onClose(callback) {
    stateChangeCallbacks['close'].add(callback);
  }

  void onError(callback) {
    stateChangeCallbacks['error'].add(callback);
  }

  void onMessage(callback) {
    stateChangeCallbacks['message'].add(callback);
  }

  void onConnOpen() {
    log('transport', 'connected to ${endPointURL()}');
    flushSendBuffer();
    reconnectTimer.reset();
    // if(!this.conn.skipHeartbeat){ // Skip heartbeat doesn't exist on dart:io Websocket
    heartbeatTimer.cancel();
    heartbeatTimer = Timer.periodic(Duration(milliseconds: heartbeatIntervalMs),
        (Timer t) => sendHeartbeat());
    // }
    stateChangeCallbacks['open'].forEach((callback) => callback());
  }

  void onConnClose(event) {
    log('transport', 'close', event);
    triggerChanError();
    heartbeatTimer.cancel();
    reconnectTimer.scheduleTimeout();
    stateChangeCallbacks['close'].forEach((callback) => callback(event));
  }

  void onConnError(error) {
    log('transport', error);
    triggerChanError();
    stateChangeCallbacks['error'].forEach((callback) => callback(error));
  }

  void triggerChanError() {
    channels
        .forEach((channel) => channel.trigger(constants.CHANNEL_EVENTS.error));
  }

  /// TODO: dart:io Websocket doesnt have connection State
  String connectionState() {
    // switch(conn && conn.readyState){
    //   case SOCKET_STATES.connecting: return "connecting"
    //   case SOCKET_STATES.open:       return "open"
    //   case SOCKET_STATES.closing:    return "closing"
    //   default:                       return "closed"
    // }
    return '';
  }

  bool isConnected() {
    return connectionState() == 'open';
  }

  void remove(Channel channel) {
    channels = channels.where((c) => c.joinRef() != channel.joinRef());
  }

  Channel channel(String topic, {Map chanParams = const {}}) {
    var chan = Channel(topic, this, params: chanParams);
    channels.add(chan);
    return chan;
  }

  void push({String topic, String event, dynamic payload, String ref}) {
    var callback = () => {
          encode({'topic': topic}, (result) => {conn.sink.add(result)})
        };

    log('push', '${topic} ${event} (${ref})', payload);

    if (isConnected()) {
      callback();
    } else {
      sendBuffer.add(callback);
    }
  }

  // Return the next message ref, accounting for overflows
  String makeRef() {
    var newRef = ref + 1;
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
      log('transport',
          'heartbeat timeout. Attempting to re-establish connection');
      conn.sink.close(constants.WS_CLOSE_NORMAL, 'hearbeat timeout');
      return;
    }

    pendingHeartbeatRef = makeRef();
    push(
        topic: 'phoenix',
        event: 'heartbeat',
        payload: {},
        ref: pendingHeartbeatRef);
  }

  void flushSendBuffer() {
    if (isConnected() && sendBuffer.isNotEmpty) {
      sendBuffer.forEach((callback) => callback());
      sendBuffer = [];
    }
  }

  void onConnMessage(rawMessage) {
    decode(rawMessage.data, (msg) {
      var topic = msg['topic'];
      var event = msg['event'];
      var payload = msg['payload'];
      var ref = msg['ref'];
      if (ref && ref == pendingHeartbeatRef) {
        pendingHeartbeatRef = null;
      }

      log(
          'receive',
          "${payload.status ?? ''} ${topic} ${event} ${ref ? '(' + ref + ')' : ''}",
          payload);

      channels.where((channel) => channel.isMember(topic)).forEach(
          (channel) => channel.trigger(event, payload: payload, ref: ref));
      stateChangeCallbacks['message'].forEach((callback) => callback(msg));
    });
  }
}
