import 'package:mocktail/mocktail.dart';
import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

class MockRealtimeClient extends Mock implements RealtimeClient {}

void main() {
  late RealtimeClient socket;
  late RealtimeSubscription channel;

  test('channel should be initially closed', () {
    final channel = RealtimeSubscription('topic', RealtimeClient('endpoint'));
    expect(channel.isClosed(), isTrue);
    channel.sendJoin(const Duration(milliseconds: 5));
    expect(channel.isJoining(), isTrue);
  });

  group('constructor', () {
    setUp(() {
      socket = RealtimeClient('', timeout: const Duration(milliseconds: 1234));
      channel = RealtimeSubscription('topic', socket, params: {'one': 'two'});
    });

    test('sets defaults', () {
      expect(channel.isClosed(), true);
      expect(channel.topic, 'topic');
      expect(channel.params, {'one': 'two'});
      expect(channel.socket, socket);
    });
  });

  group('join', () {
    setUp(() {
      socket = RealtimeClient('wss://example.com/socket');
      channel = socket.channel('topic', chanParams: {'one': 'two'});
    });

    test('sets state to joining', () {
      channel.subscribe();

      expect(channel.isJoining(), true);
    });

    test('throws if attempting to join multiple times', () {
      channel.subscribe();

      expect(() => channel.subscribe(), throwsA(const TypeMatcher<String>()));
    });

    test('can set timeout on joinPush', () {
      const newTimeout = Duration(milliseconds: 2000);
      final joinPush = channel.subscribe(timeout: newTimeout);

      expect(joinPush.timeout, const Duration(milliseconds: 2000));
    });
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
