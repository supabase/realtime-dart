import 'lib/constants.dart' as constants;
import 'lib/push.dart';
import 'lib/retry_timer.dart';
import 'socket.dart';

typedef Callback = void Function(dynamic payload, {String ref});

class Channel {
  Channel(this.topic, this.params, this.socket);

  String state = constants.CHANNEL_STATES.closed;
  String topic;
  Map params;
  Socket socket;
  List bindings;

  bool isMember(topic) {
    return this.topic == topic;
  }

  void on(String event, Callback callback) {
    bindings.add({'event': event, 'callback': callback});
  }

  void off(String event) {
    bindings = bindings.where((bind) => bind.event != event);
  }

  void trigger(String event, {dynamic payload, String ref}) {
    // let {close, error, leave, join} = CHANNEL_EVENTS
    // if(ref && [close, error, leave, join].indexOf(event) >= 0 && ref !== this.joinRef()){
    //   return
    // }
    // let handledPayload = this.onMessage(event, payload, ref)
    // if(payload && !handledPayload){ throw("channel onMessage callbacks must return the payload, modified or unmodified") }

    // this.bindings.filter( bind => bind.event === event)
    //              .map( bind => bind.callback(handledPayload, ref))
  }

  String replyEventName(String ref) {
    return 'chan_reply_${ref}';
  }
}
