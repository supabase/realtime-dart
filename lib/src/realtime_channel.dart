import 'package:realtime_client/src/constants.dart';
import 'package:realtime_client/src/push.dart';
import 'package:realtime_client/src/realtime_client.dart';
import 'package:realtime_client/src/realtime_presence.dart';
import 'package:realtime_client/src/retry_timer.dart';

typedef BindingCallback = void Function(dynamic payload, [String? ref]);

class Binding {
  String type;
  Map<String, String> filter;
  BindingCallback callback;

  Binding(this.type, this.filter, this.callback);
}

class RealtimeChannel {
  List<Binding> _bindings = [];
  final Duration _timeout;
  ChannelStates _state = ChannelStates.closed;
  bool joinedOnce = false;
  late Push _joinPush;
  late RetryTimer _rejoinTimer;
  List<Push> _pushBuffer = [];
  late RealtimePresence presence;

  final String topic;
  final Map<String, dynamic> params;
  final RealtimeClient socket;

  RealtimeChannel(this.topic, this.socket, {this.params = const {}})
      : _timeout = socket.timeout {
    _joinPush = Push(this, ChannelEvents.join, params, _timeout);
    _rejoinTimer =
        RetryTimer(() => rejoinUntilConnected(), socket.reconnectAfterMs);
    _joinPush.receive('ok', (_) {
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

    _joinPush.receive('timeout', (_) {
      if (!isJoining) return;
      socket.log('channel', 'timeout $topic', _joinPush.timeout);
      _state = ChannelStates.errored;
      _rejoinTimer.scheduleTimeout();
    });

    on(
      ChannelEvents.reply.eventName(),
      {},
      (payload, [ref]) => trigger(
        replyEventName(ref),
        payload,
      ),
    );

    presence = RealtimePresence(this);
    presence.onJoin((key, currentPresences, newPresences) {
      trigger('presence', {
        'event': 'join',
        'key': key,
        'currentPresences': currentPresences,
        'newPresences': newPresences,
      });
    });
    presence.onLeave((key, currentPresences, leftPresences) => {
          trigger('presence', {
            'event': 'leave',
            'key': key,
            'currentPresences': currentPresences,
            'leftPresences': leftPresences,
          })
        });
    presence.onSync(() => {
          trigger('presence', {'event': 'sync'})
        });
  }

  void rejoinUntilConnected() {
    _rejoinTimer.scheduleTimeout();
    if (socket.isConnected) rejoin();
  }

  Push subscribe({Duration? timeout}) {
    if (joinedOnce == true) {
      throw "tried to subscribe multiple times. 'subscribe' can only be called a single time per channel instance";
    } else {
      final configs = _bindings.fold<Map<String, dynamic>>({}, (acc, binding) {
        final type = binding.type;
        if (![
          'phx_close',
          'phx_error',
          'phx_reply',
          'presence_diff',
          'presence_state',
        ].contains(type)) {
          acc[type] = binding;
        }
        return acc;
      });

      if (configs.keys.isNotEmpty) {
        updateJoinPayload(<String, dynamic>{'configs': configs});
      }

      joinedOnce = true;
      rejoin(timeout ?? _timeout);
      return _joinPush;
    }
  }

  /// Registers a callback that will be executed when the channel closes.
  void onClose(Function callback) {
    on(ChannelEvents.close.eventName(), {}, (reason, [ref]) => callback());
  }

  /// Registers a callback that will be executed when the channel encounteres an error.
  void onError(void Function(String?) callback) {
    on(
      ChannelEvents.error.eventName(),
      {},
      (reason, [ref]) => callback(reason.toString()),
    );
  }

  RealtimeChannel on(
    String type, [
    Map<String, String>? filter,
    BindingCallback? callback,
  ]) {
    _bindings.add(Binding(
      type,
      filter ?? <String, String>{},
      callback ?? (_, [__]) {},
    ));
    return this;
  }

  RealtimeChannel off(String type, Map<String, String> filter) {
    _bindings = _bindings.where((bind) {
      return !(bind.type == type &&
          RealtimeChannel._isEqual(bind.filter, filter));
    }).toList();
    return this;
  }

  /// Returns `true` if the socket is connected and the channel has been joined.
  bool get canPush {
    return socket.isConnected && isJoined;
  }

  Push push(
    ChannelEvents event,
    Map<String, String> payload, [
    Duration? timeout,
  ]) {
    if (!joinedOnce) {
      throw "tried to push '${event.eventName()}' to '$topic' before joining. Use channel.subscribe() before pushing events";
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
  Push unsubscribe([Duration? timeout]) {
    _state = ChannelStates.leaving;
    void onClose() {
      socket.log('channel', 'leave $topic');
      trigger(ChannelEvents.close.eventName(), {'type': 'leave'}, joinRef);
    }

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
  dynamic onMessage(String event, dynamic payload, [String? ref]) {
    return payload;
  }

  bool isMember(String? topic) {
    return this.topic == topic;
  }

  String get joinRef => _joinPush.ref;

  void rejoin([Duration? timeout]) {
    if (isLeaving) return;
    socket.leaveOpenTopic(topic);
    _state = ChannelStates.joining;
    _joinPush.resend(timeout ?? _timeout);
  }

  void trigger(String type, [dynamic payload, String? ref]) {
    final events = [
      ChannelEvents.close,
      ChannelEvents.error,
      ChannelEvents.leave,
      ChannelEvents.join,
    ].map((e) => e.eventName()).toSet();

    if (ref != null && events.contains(type) && ref != joinRef) return;

    final handledPayload = onMessage(type, payload, ref);
    if (payload != null && handledPayload == null) {
      throw 'channel onMessage callbacks must return the payload, modified or unmodified';
    }

    final filtered = _bindings.where((bind) {
      return bind.type == type &&
          (bind.filter['event'] == '*' ||
              bind.filter['event'] == payload?['event']);
    });
    for (final bind in filtered) {
      bind.callback(handledPayload, ref);
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

  static _isEqual(Map<String, String> obj1, Map<String, String> obj2) {
    if (obj1.keys.length != obj2.keys.length) {
      return false;
    }

    for (final k in obj1.keys) {
      if (obj1[k] != obj2[k]) {
        return false;
      }
    }

    return true;
  }
}
