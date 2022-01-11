import 'dart:async';

import 'package:realtime_client/src/constants.dart';
import 'package:realtime_client/src/message.dart';
import 'package:realtime_client/src/realtime_subscription.dart';

typedef Callback = void Function(dynamic response);

/// Push event obj
class Push {
  final RealtimeSubscription _channel;
  final ChannelEvents _event;
  String? _ref;
  String? _refEvent;
  final Map<String, dynamic> payload;
  dynamic _receivedResp;
  Duration _timeout;
  Timer? _timeoutTimer;
  final List<Hook> _recHooks = [];
  bool sent = false;

  /// Initializes the Push
  ///
  /// `channel` The Channel
  /// `event` The event, for example `"phx_join"`
  /// `payload` The payload, for example `{user_id: 123}`
  /// `timeout` The push timeout in milliseconds
  Push(
    this._channel,
    this._event, [
    this.payload = const {},
    this._timeout = Constants.defaultTimeout,
  ]);

  String? get ref => _ref;

  Duration get timeout => _timeout;

  void resend(Duration timeout) {
    _timeout = timeout;
    cancelRefEvent();
    _ref = '';
    _refEvent = null;
    _receivedResp = null;
    sent = false;
    send();
  }

  void send() {
    if (_hasReceived('timeout')) return;

    startTimeout();
    sent = true;
    final message = Message(
      topic: _channel.topic,
      payload: payload,
      event: _event,
      ref: ref,
    );
    _channel.socket.push(message);
  }

  void updatePayload(Map<String, dynamic> payload) {
    payload.addAll(this.payload);
  }

  Push receive(String status, Callback callback) {
    if (_hasReceived(status)) {
      callback(_receivedResp['response']);
    }

    _recHooks.add(Hook(status, callback));
    return this;
  }

  void startTimeout() {
    if (_timeoutTimer != null) return;

    _ref = _channel.socket.makeRef();
    final event = _channel.replyEventName(ref);
    _refEvent = event;

    _channel.on(event, (dynamic payload, {ref}) {
      cancelRefEvent();
      cancelTimeout();
      _receivedResp = payload;
      matchReceive(payload['status'] as String, payload['response']);
    });

    _timeoutTimer = Timer(timeout, () {
      trigger('timeout', {});
    });
  }

  void trigger(String status, dynamic response) {
    if (_refEvent != null) {
      _channel.trigger(
        _refEvent!,
        payload: {
          'status': status,
          'response': response,
        },
      );
    }
  }

  void cancelRefEvent() {
    if (_refEvent == null) {
      return;
    }
    _channel.off(_refEvent!);
  }

  void cancelTimeout() {
    _timeoutTimer!.cancel();
    _timeoutTimer = null;
  }

  void matchReceive(String status, dynamic response) {
    _recHooks
        .where((h) => h.status == status)
        .forEach((h) => h.callback(response));
  }

  bool _hasReceived(String status) {
    return _receivedResp != null &&
        _receivedResp is Map &&
        _receivedResp['status'] == status;
  }
}

class Hook {
  String status;
  Callback callback;

  Hook(this.status, this.callback);
}
