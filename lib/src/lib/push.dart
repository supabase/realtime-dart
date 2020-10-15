import 'dart:async';

import '../channel.dart';
import 'constants.dart' as constants;

typedef Callback = void Function(dynamic response);

/// Initializes the Push
///
/// `channel` The Channel
/// `event` The event, for example `"phx_join"`
/// `payload` The payload, for example `{user_id: 123}`
/// `timeout` The push timeout in milliseconds
class Push {
  Channel channel;
  String event;
  String ref;
  String refEvent;
  dynamic payload;
  dynamic receivedResp;
  int timeout;
  Timer timeoutTimer;
  List recHooks = [];
  bool sent;

  Push({
    this.channel,
    this.event,
    this.payload = const {},
    this.timeout = constants.DEFAULT_TIMEOUT,
  });

  void resend(int timeout) {
    this.timeout = timeout;
    cancelRefEvent();
    ref = null;
    refEvent = null;
    receivedResp = null;
    sent = false;
    send();
  }

  void send() {
    if (_hasReceived('timeout')) return;

    _startTimeout();
    sent = true;
    channel.socket.push(
      topic: channel.topic,
      event: event,
      payload: payload,
      ref: ref,
    );
  }

  Push receive(String status, Callback callback) {
    if (_hasReceived(status)) {
      callback(receivedResp?.response);
    }

    recHooks.add({'status': status, 'callback': callback});
    return this;
  }

  void _startTimeout() {
    if (timeoutTimer == null) return;

    ref = channel.socket.makeRef();
    refEvent = channel.replyEventName(ref);

    channel.on(refEvent, (dynamic payload, {ref}) {
      cancelRefEvent();
      cancelTimeout();
      receivedResp = payload;
      matchReceive(payload['status'], payload['response']);
    });

    timeoutTimer = Timer(Duration(milliseconds: timeout), () {
      _trigger('timeout', {});
    });
  }

  void _trigger(status, response) {
    if (refEvent != null) {
      channel.trigger(refEvent, payload: {
        'status': status,
        'response': response,
      });
    }
  }

  void cancelRefEvent() {
    if (refEvent == null) {
      return;
    }
    channel.off(refEvent);
  }

  void cancelTimeout() {
    timeoutTimer.cancel();
    timeoutTimer = null;
  }

  void matchReceive(String status, dynamic response) {
    recHooks
        .where((h) => h.status == status)
        .forEach((h) => h.callback(response));
  }

  bool _hasReceived(String status) {
    return receivedResp && receivedResp.status == status;
  }
}
