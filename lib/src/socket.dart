import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:web_socket_channel/io.dart';

import 'lib/constants.dart' as constants;
import 'channel.dart';
import 'lib/retry_timer.dart';

class Socket {
  Socket(
    String endPoint, {
    String transport,
    Function encode,
    Function decode,
    int timeout,
    int heartbeatIntervalMs,
    Function reconnectAfterMs,
    Function logger,
    int longpollerTimeout,
    Map params,
  });

  Map<String, List<Function>> stateChangeCallbacks = {
    'open': [],
    'close': [],
    'error': [],
    'message': []
  };
  List<Channel> channels = [];
  List sendBuffer = [];
  IOWebSocketChannel conn;
  int ref = 0;
  int timeout = constants.DEFAULT_TIMEOUT;
  String transport = constants.TRANSPORTS.websocket;
  Function defaultEncoder =
      (dynamic payload, Function callback) => callback(json.encode(payload));
  Function defaultDecoder =
      (dynamic payload, Function callback) => callback(json.decode(payload));
  int heartbeatIntervalMs = 30000;
  Function encode;
  Function decode;
  Function reconnectAfterMs;
  Function logger;
  int longpollerTimeout;
  Map params;
  Map headers;
  String endPoint;
  Timer heartbeatTimer;
  String pendingHeartbeatRef;
  RetryTimer reconnectTimer;

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
  }

  /// Logs the message. Override `this.logger` for specialized logging. noops by default
  void log([String kind, String msg, dynamic data]) {
    logger(kind, msg, data);
  }

  /// Registers callbacks for connection state change events
  ///
  /// Examples
  ///
  ///    socket.onError(function(error){ alert("An error occurred") })
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
    // flushSendBuffer();
    reconnectTimer.reset();
    // if(!this.conn.skipHeartbeat){
    //   clearInterval(this.heartbeatTimer);
    //   this.heartbeatTimer = setInterval(() => this.sendHeartbeat(), this.heartbeatIntervalMs);
    // }
    stateChangeCallbacks['open'].forEach((callback) => callback());
  }

  void onConnClose(event) {
    log('transport', 'close', event);
    // this.triggerChanError();
    heartbeatTimer.cancel();
    reconnectTimer.scheduleTimeout();
    stateChangeCallbacks['close'].forEach((callback) => callback(event));
  }

  void onConnError(error) {
    log('transport', error);
    // this.triggerChanError();
    stateChangeCallbacks['error'].forEach((callback) => callback(error));
  }

  void triggerChanError() {
    channels
        .forEach((channel) => channel.trigger(constants.CHANNEL_EVENTS.error));
  }

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
    // channels = channels.where((c) => c.joinRef() !== channel.joinRef())
  }

  Channel channel(String topic, {Map chanParams = const {}}) {
    var chan = Channel(topic, chanParams, this);
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
