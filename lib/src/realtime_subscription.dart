import 'package:realtime_client/src/bind.dart';
import 'package:realtime_client/src/constants.dart';
import 'package:realtime_client/src/push.dart';
import 'package:realtime_client/src/realtime_client.dart';
import 'package:realtime_client/src/retry_timer.dart';

class RealtimeSubscription {
  ChannelStates _state = ChannelStates.closed;
  final String topic;
  final Map<String, dynamic> params;
  final RealtimeClient socket;
  late RetryTimer _rejoinTimer;
  List<Push> _pushBuffer = [];
  List<Binding> _bindings = [];
  bool joinedOnce = false;
  late Push _joinPush;
  final Duration _timeout;

  RealtimeSubscription(this.topic, this.socket, {this.params = const {}})
      : _timeout = socket.timeout {
    _joinPush = Push(this, ChannelEvents.join, params, _timeout);
    _rejoinTimer =
        RetryTimer(() => rejoinUntilConnected(), socket.reconnectAfterMs);
    _joinPush.receive('ok', (response) {
      _state = ChannelStates.joined;
      _rejoinTimer.reset();
      for (final pushEvent in _pushBuffer) {
        pushEvent.send();
      }
      _pushBuffer = [];
    });

    onClose(() {
      _rejoinTimer.reset();
      socket.log('channel', 'close $topic $joinRef');
      _state = ChannelStates.closed;
      socket.remove(this);
    });

    onError((String? reason) {
      if (isLeaving || isClosed) return;
      socket.log('channel', 'error $topic', reason);
      _state = ChannelStates.errored;
      _rejoinTimer.scheduleTimeout();
    });

    _joinPush.receive('timeout', (response) {
      if (!isJoining) return;
      socket.log('channel', 'timeout $topic', _joinPush.timeout);
      _state = ChannelStates.errored;
      _rejoinTimer.scheduleTimeout();
    });

    on(
      ChannelEvents.reply.name,
      (payload, {ref}) => trigger(
        replyEventName(ref),
        payload: payload,
      ),
    );
  }

  void rejoinUntilConnected() {
    _rejoinTimer.scheduleTimeout();
    if (socket.isConnected) rejoin();
  }

  Push subscribe({Duration? timeout}) {
    if (joinedOnce == true) {
      throw "tried to subscribe multiple times. 'subscribe' can only be called a single time per channel instance";
    } else {
      joinedOnce = true;
      rejoin(timeout ?? _timeout);
      return _joinPush;
    }
  }

  void onClose(Function callback) {
    on(ChannelEvents.close.name, (reason, {ref}) => callback());
  }

  void onError(void Function(String?) callback) {
    on(
      ChannelEvents.error.name,
      (reason, {ref}) => callback(reason.toString()),
    );
  }

  void on(String event, BindingCallback callback) {
    _bindings.add(Binding(event: event, callback: callback));
  }

  void off(String event) {
    _bindings = _bindings.where((bind) => bind.event != event).toList();
  }

  bool get canPush {
    return socket.isConnected && isJoined;
  }

  Push push(
    ChannelEvents event,
    Map<String, String> payload, {
    Duration? timeout,
  }) {
    if (!joinedOnce) {
      throw "tried to push '${event.name}' to '$topic' before joining. Use channel.subscribe() before pushing events";
    }
    final pushEvent = Push(this, event, payload, timeout ?? _timeout);
    if (canPush) {
      pushEvent.send();
    } else {
      pushEvent.startTimeout();
      _pushBuffer.add(pushEvent);
    }

    return pushEvent;
  }

  void updateJoinPayload(Map<String, dynamic> payload) {
    _joinPush.updatePayload(payload);
  }

  /// Leaves the channel
  ///
  /// Unsubscribes from server events, and instructs channel to terminate on server.
  /// Triggers onClose() hooks.
  ///
  /// To receive leave acknowledgements, use the a `receive` hook to bind to the server ack,
  /// ```dart
  /// channel.unsubscribe().receive("ok", (_){print("left!");} );
  /// ```
  Push unsubscribe({Duration? timeout}) {
    void onClose() {
      socket.log('channel', 'leave $topic');
      trigger(
        ChannelEvents.close.name,
        payload: {'type': 'leave'},
        ref: joinRef,
      );
    }

    _state = ChannelStates.leaving;

    // Destroy joinPush to avoid connection timeouts during unscription phase
    _joinPush.destroy();

    final leavePush = Push(this, ChannelEvents.leave, {}, timeout ?? _timeout);
    leavePush
        .receive('ok', (_) => onClose())
        .receive('timeout', (_) => onClose());
    leavePush.send();
    if (!canPush) {
      leavePush.trigger('ok', {});
    }

    return leavePush;
  }

  /// Overridable message hook
  ///
  /// Receives all events for specialized message handling before dispatching to the channel callbacks.
  /// Must return the payload, modified or unmodified.
  dynamic onMessage(String event, dynamic payload, {String? ref}) {
    return payload;
  }

  bool isMember(String? topic) {
    return this.topic == topic;
  }

  String? get joinRef => _joinPush.ref;

  void rejoin([Duration? timeout]) {
    if (isLeaving) return;
    socket.leaveOpenTopic(topic);
    _state = ChannelStates.joining;
    _joinPush.resend(timeout ?? _timeout);
  }

  void trigger(String event, {dynamic payload, String? ref}) {
    final events = [
      ChannelEvents.close,
      ChannelEvents.error,
      ChannelEvents.leave,
      ChannelEvents.join,
    ].map((e) => e.name).toSet();

    if (ref != null && events.contains(event) && ref != joinRef) return;

    final handledPayload = onMessage(event, payload, ref: ref);
    if (payload != null && handledPayload == null) {
      throw 'channel onMessage callbacks must return the payload, modified or unmodified';
    }

    final filtered = _bindings.where((bind) {
      /// bind all realtime events
      if (bind.event == '*') {
        return event == (payload is Map ? payload['type'] : payload);
      } else {
        return bind.event == event;
      }
    });
    for (final bind in filtered) {
      bind.callback(handledPayload, ref: ref);
    }
  }

  String replyEventName(String? ref) {
    return 'chan_reply_$ref';
  }

  bool get isClosed => _state == ChannelStates.closed;

  bool get isErrored => _state == ChannelStates.errored;

  bool get isJoined => _state == ChannelStates.joined;

  bool get isJoining => _state == ChannelStates.joining;

  bool get isLeaving => _state == ChannelStates.leaving;
}
