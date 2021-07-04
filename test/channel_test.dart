import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main() {
  test('channel should be initially closed', () {
    final channel = RealtimeSubscription('topic', RealtimeClient('endpoint'));
    expect(channel.isClosed(), isTrue);
    channel.sendJoin(const Duration(seconds: 5));
    expect(channel.isJoining(), isTrue);
  });

  group('on', () {
    late RealtimeSubscription channel;

    setUp(() {
      channel = RealtimeSubscription('topic', RealtimeClient('endpoint'));
    });

    test('sets up callback for event', () {
      var callbackCalled = 0;
      channel.on('event', (dynamic payload, {String? ref}) => callbackCalled++);

      channel.trigger('event', payload: {});
      expect(callbackCalled, 1);
    });

    test('other event callbacks are ignored', () {
      var eventCallbackCalled = 0;
      var otherEventCallbackCalled = 0;
      channel.on(
          'event', (dynamic payload, {String? ref}) => eventCallbackCalled++);
      channel.on('otherEvent',
          (dynamic payload, {String? ref}) => otherEventCallbackCalled++);

      channel.trigger('event', payload: {});
      expect(eventCallbackCalled, 1);
      expect(otherEventCallbackCalled, 0);
    });

    test('"*" bind all events', () {
      var callbackCalled = 0;
      channel.on('*', (dynamic payload, {String? ref}) => callbackCalled++);

      channel.trigger('INSERT', payload: {});
      expect(callbackCalled, 0);

      channel.trigger('*', payload: {'type': 'INSERT'});
      expect(callbackCalled, 0);

      channel.trigger('INSERT', payload: {'type': 'INSERT'});
      channel.trigger('UPDATE', payload: {'type': 'UPDATE'});
      channel.trigger('DELETE', payload: {'type': 'DELETE'});
      expect(callbackCalled, 3);
    });
  });
}
