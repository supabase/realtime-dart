import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realtime_client/realtime_client.dart';
import 'package:realtime_client/src/constants.dart';
import 'package:test/test.dart';

void main() {
  late RealtimeClient socket;
  late RealtimeSubscription channel;

  const defaultRef = 1;

  test('channel should be initially closed', () {
    final channel = RealtimeSubscription('topic', RealtimeClient('endpoint'));
    expect(channel.isClosed(), isTrue);
    channel.sendJoin(const Duration(seconds: 5));
    expect(channel.isJoining(), isTrue);
  });

  group('constructor', () {
    setUp(() {
      socket = RealtimeClient('', timeout: const Duration(seconds: 1234));
      channel = RealtimeSubscription('topic', socket, params: {'one': 'two'});
    });

    test('sets defaults', () {
      expect(channel.isClosed(), true);
      expect(channel.topic, 'topic');
      expect(channel.params, {'one': 'two'});
      expect(channel.socket, socket);
    });

    test('sets up joinPush object', () {
      final joinPush = channel.subscribe();
      // const joinPush = channel.joinPush;

      // expect(joinPush.channel, matcher)
      expect(joinPush.payload, {'one': 'two'});
      // expect(joinPush.event, 'phx_join);
      expect(joinPush.timeout, const Duration(seconds: 1234));

      // assert.deepEqual(joinPush.channel, channel)
      // assert.deepEqual(joinPush.payload, { one: 'two' })
      // assert.equal(joinPush.event, 'phx_join')
      // assert.equal(joinPush.timeout, 1234)
    });
  });

  group('join', () {
    setUp(() {
      socket = RealtimeClient('wss://example.com/socket');
      channel = socket.channel('topic', chanParams: {'one': 'two'});
    });

    test('sets state to joining', () {
      channel.subscribe();

      // expect(channel.state, 'joining');
      // assert.equal(channel.state, 'joining')
    });

    test('sets joinedOnce to true', () {
      // expect(channel.joinnedOnce, false);
      // assert.ok(!channel.joinedOnce)

      channel.subscribe();

      // expect(channel.joinnedOnce, true);
      // assert.ok(channel.joinedOnce)
    });

    test('throws if attempting to join multiple times', () {
      channel.subscribe();

      expect(() => channel.subscribe(), throwsA(const TypeMatcher<String>()));
    });

    test('triggers socket push with channel params', () {
      // sinon.stub(socket, 'makeRef').callsFake(() => defaultRef)
      // const spy = sinon.spy(socket, 'push')

      channel.subscribe();

      // assert.ok(spy.calledOnce)
      // assert.ok(
      //   spy.calledWith({
      //     topic: 'topic',
      //     event: 'phx_join',
      //     payload: { one: 'two' },
      //     ref: defaultRef,
      //   })
      // );
    });

    test('can set timeout on joinPush', () {
      const newTimeout = Duration(seconds: 2000);
      final joinPush = channel.subscribe(timeout: newTimeout);

      expect(joinPush.timeout, const Duration(seconds: 2000));
    });

    group('timeout behavior', () {
      T runWithTiming<T>(T Function() callback) {
        return callback();
      }

      test('succeeds before timeout', () {
        final timeout = socket.timeout;

        FakeAsync().run((async) {
          runWithTiming(() {
            socket.connect();
            async.elapse(timeout ~/ 2);
            channel.trigger('ok');
            // expect(channel.state, 'joined');
            // assert.equal(channel.state, 'joined')
            async.elapse(timeout);
            // expect(push called, 1);
            // assert.equal(spy.callCount, 1)
          });
        });
      });
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
