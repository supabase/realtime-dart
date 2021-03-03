import 'constants.dart';

class Message {
  String topic;
  ChannelEvents event;
  dynamic payload;
  String? ref;

  Message({
    required this.topic,
    required this.event,
    required this.payload,
    required this.ref,
  });

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'event': event.eventName(),
        'payload': payload,
        'ref': ref
      };
}
