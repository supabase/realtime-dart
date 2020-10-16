import 'lib/constants.dart' as constants;
import 'lib/push.dart';
import 'lib/retry_timer.dart';
import 'socket.dart';

typedef Callback = void Function(dynamic payload, {String ref});

class Channel {
  String state = constants.CHANNEL_STATES.closed;
  String topic;
  Map params;
  Socket socket;
  RetryTimer rejoinTimer;
  List<Push> pushBuffer = [];
  List bindings;
  bool joinedOnce;
  Push joinPush;
  int timeout;

  Channel(String topic, Socket socket, {Map params = const {}}) {
    this.topic = topic;
    this.socket = socket;
    this.params = params;

    timeout = this.socket.timeout;
    joinPush = Push(this, constants.CHANNEL_EVENTS.join,
        payload: this.params, timeout: timeout);
    rejoinTimer =
        RetryTimer(() => rejoinUntilConnected(), this.socket.reconnectAfterMs);

    joinPush.receive('ok', (response) {
      state = constants.CHANNEL_STATES.joined;
      rejoinTimer.reset();
      pushBuffer.forEach((pushEvent) => pushEvent.send());
      pushBuffer = [];
    });

    onClose(() {
      rejoinTimer.reset();
      this.socket.log('channel', 'close ${this.topic} ${joinRef()}');
      state = constants.CHANNEL_STATES.closed;
      this.socket.remove(this);
    });

    onError((String reason) {
      if (isLeaving() || isClosed()) {
        return;
      }
      this.socket.log('channel', 'error ${this.topic}', reason);
      state = constants.CHANNEL_STATES.errored;
      rejoinTimer.scheduleTimeout();
    });

    joinPush.receive('timeout', (response) {
      if (!isJoining()) {
        return;
      }
      this.socket.log('channel', 'timeout ${this.topic}', joinPush.timeout);
      state = constants.CHANNEL_STATES.errored;
      rejoinTimer.scheduleTimeout();
    });

    on(constants.CHANNEL_EVENTS.reply,
        (payload, {ref}) => trigger(replyEventName(ref), payload: payload));
  }

  void rejoinUntilConnected() {
    rejoinTimer.scheduleTimeout();
    if (socket.isConnected()) {
      rejoin();
    }
  }

  Push subscribe([int timeout]) {
    if (joinedOnce) {
      throw "tried to subscribe multiple times. 'subscribe' can only be called a single time per channel instance";
    } else {
      joinedOnce = true;
      rejoin(timeout ?? this.timeout);
      return joinPush;
    }
  }

  void onClose(Function callback) {
    on(constants.CHANNEL_EVENTS.close, (reason, {ref}) => callback());
  }

  void onError(Function(String) callback) {
    on(constants.CHANNEL_EVENTS.error, (reason, {ref}) => callback(reason));
  }

  void on(String event, Callback callback) {
    bindings.add({'event': event, 'callback': callback});
  }

  void off(String event) {
    bindings = bindings.where((bind) => bind.event != event);
  }

  bool canPush() {
    return socket.isConnected() && isJoined();
  }

  Push push(constants.CHANNEL_STATES event, dynamic payload, {int timeout}) {
    if (!joinedOnce) {
      throw "tried to push '${event}' to '${topic}' before joining. Use channel.subscribe() before pushing events";
    }
    var pushEvent = Push(this, event.toString(),
        payload: payload, timeout: timeout ?? this.timeout);
    if (canPush()) {
      pushEvent.send();
    } else {
      pushEvent.startTimeout();
      pushBuffer.add(pushEvent);
    }

    return pushEvent;
  }

  /// Leaves the channel
  ///
  /// Unsubscribes from server events, and instructs channel to terminate on server.
  /// Triggers onClose() hooks.
  ///
  /// To receive leave acknowledgements, use the a `receive` hook to bind to the server ack,
  /// ```dart
  /// channel.unsubscribe().receive("ok", () => alert("left!") )
  /// ```
  Push unsubscribe([int timeout]) {
    state = constants.CHANNEL_STATES.leaving;
    var onClose = () {
      socket.log('channel', 'leave ${topic}');
      trigger(constants.CHANNEL_EVENTS.close, payload: 'leave', ref: joinRef());
    };
    var leavePush = Push(this, constants.CHANNEL_EVENTS.leave,
        timeout: timeout ?? this.timeout);
    leavePush
        .receive('ok', (_) => onClose())
        .receive('timeout', (_) => onClose());
    leavePush.send();
    if (!canPush()) {
      leavePush.trigger('ok', {});
    }

    return leavePush;
  }

  /// Overridable message hook
  ///
  /// Receives all events for specialized message handling before dispatching to the channel callbacks.
  /// Must return the payload, modified or unmodified.
  dynamic onMessage(String event, dynamic payload, {String ref}) {
    return payload;
  }

  bool isMember(topic) {
    return this.topic == topic;
  }

  String joinRef() {
    return joinPush.ref;
  }

  void sendJoin(int timeout) {
    state = constants.CHANNEL_STATES.joining;
    joinPush.resend(timeout);
  }

  void rejoin([int timeout]) {
    if (isLeaving()) {
      return;
    }
    sendJoin(timeout ?? this.timeout);
  }

  void trigger(String event, {dynamic payload, String ref}) {
    var events = [
      constants.CHANNEL_EVENTS.close,
      constants.CHANNEL_EVENTS.error,
      constants.CHANNEL_EVENTS.leave,
      constants.CHANNEL_EVENTS.join
    ];

    if (ref != null && events.contains(event) && ref != joinRef()) {
      return;
    }
    var handledPayload = onMessage(event, payload, ref: ref);
    if (payload && !handledPayload) {
      throw 'channel onMessage callbacks must return the payload, modified or unmodified';
    }

    bindings
        .where((bind) => bind.event == event)
        .map((bind) => bind.callback(handledPayload, ref));
  }

  String replyEventName(String ref) {
    return 'chan_reply_${ref}';
  }

  bool isClosed() {
    return state == constants.CHANNEL_STATES.closed;
  }

  bool isErrored() {
    return state == constants.CHANNEL_STATES.errored;
  }

  bool isJoined() {
    return state == constants.CHANNEL_STATES.joined;
  }

  bool isJoining() {
    return state == constants.CHANNEL_STATES.joining;
  }

  bool isLeaving() {
    return state == constants.CHANNEL_STATES.leaving;
  }
}
