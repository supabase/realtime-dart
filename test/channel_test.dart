import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main() {
  late RealtimeClient socket;
  late RealtimeSubscription channel;

  const defaultRef = '1';

  test('channel should be initially closed', () {
    final channel = RealtimeSubscription('topic', RealtimeClient('endpoint'));
    expect(channel.isClosed(), isTrue);
    channel.sendJoin(const Duration(seconds: 5));
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

  group('onError', () {
    setUp(() {
      socket = RealtimeClient('/socket');
      channel = socket.channel('topic', chanParams: {'one': 'two'});
      channel.subscribe();
    });

    test("sets state to 'errored'", () {
      expect(channel.isErrored(), false);

      channel.trigger('phx_error');

      expect(channel.isErrored(), true);
    });
  });

  group('onClose', () {
    setUp(() {
      socket = RealtimeClient('/socket');
      channel = socket.channel('topic', chanParams: {'one': 'two'});
      channel.subscribe();
    });

    test("sets state to 'closed'", () {
      expect(channel.isClosed(), false);

      channel.trigger('phx_close');

      expect(channel.isClosed(), true);
    });
  });

  group('onMessage', () {
    setUp(() {
      socket = RealtimeClient('/socket');

      channel = socket.channel('topic', chanParams: {'one': 'two'});
    });

    test('returns payload by default', () {
      final payload = channel.onMessage('event', {'one': 'two'});

      expect(payload, {'one': 'two'});
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

  group('off', () {
    setUp(() {
      socket = RealtimeClient('/socket');

      channel = socket.channel('topic', chanParams: {'one': 'two'});
    });

    test('removes all callbacks for event', () {
      var callBackEventCalled1 = 0;
      var callbackEventCalled2 = 0;
      var callbackOtherCalled = 0;

      channel.on(
          'event', (dynamic payload, {String? ref}) => callBackEventCalled1++);
      channel.on(
          'event', (dynamic payload, {String? ref}) => callbackEventCalled2++);
      channel.on(
          'other', (dynamic payload, {String? ref}) => callbackOtherCalled++);

      channel.off('event');

      channel.trigger('event', payload: {}, ref: defaultRef);
      channel.trigger('other', payload: {}, ref: defaultRef);

      expect(callBackEventCalled1, 0);
      expect(callbackEventCalled2, 0);
      expect(callbackOtherCalled, 1);
    });
  });

  group('unsubscribe', () {
    setUp(() {
      socket = RealtimeClient('/socket');

      channel = socket.channel('topic', chanParams: {'one': 'two'});
      channel.subscribe().trigger('ok', {});
    });

    test("closes channel on 'ok' from server", () {
      final anotherChannel =
          socket.channel('another', chanParams: {'three': 'four'});
      expect(socket.channels.length, 2);

      channel.unsubscribe().trigger('ok', {});

      expect(socket.channels.length, 1);
      expect(socket.channels[0].topic, anotherChannel.topic);
    });

    test("sets state to closed on 'ok' event", () {
      expect(channel.isClosed(), false);

      channel.unsubscribe().trigger('ok', {});

      expect(channel.isClosed(), true);
    });

    test("able to unsubscribe from * subscription", () {
      channel.on('*', (payload, {ref}) {});
      expect(socket.channels.length, 1);

      channel.unsubscribe().trigger('ok', {});

      expect(socket.channels.length, 0);
    });
  });
}
