import 'constants.dart';

class Message {
  String topic;
  ChannelEvents event;
  dynamic payload;
  String ref;

  Message({this.topic, this.event, this.payload, this.ref});

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'event': event.eventName(),
        'payload': payload,
        'ref': ref
      };
}