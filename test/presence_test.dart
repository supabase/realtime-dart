import 'package:realtime_client/src/realtime_presence.dart';
import 'package:test/test.dart';

extension on PresenceState {
  /// Flattens the complex array structure to easily comparable format.
  Map toMap() {
    return presences.entries.fold<Map>(
        {},
        (previousValue, element) => {
              ...previousValue,
              element.key: element.value
                  .map((e) => {...e.payload, 'presence_id': e.presenceId})
            });
  }
}

class Fixtures {
  static RawPresenceState rawState() {
    return RawPresenceState({
      'u1': {
        'metas': [
          {'id': 1, 'phx_ref': '1'}
        ]
      },
      'u2': {
        'metas': [
          {'id': 2, 'phx_ref': '2'}
        ]
      },
      'u3': {
        'metas': [
          {'id': 3, 'phx_ref': '3'}
        ]
      },
    });
  }

  static PresenceState transformedState() {
    return PresenceState({
      'u1': [
        Presence({'id': 1, 'presence_id': '1'})
      ],
      'u2': [
        Presence({'id': 2, 'presence_id': '2'})
      ],
      'u3': [
        Presence({'id': 3, 'presence_id': '3'})
      ],
    });
  }
}

void main() {
  group('syncState', () {
    test('syncs empty state', () {
      var state = PresenceState({});
      final newState = PresenceState({
        'u1': [
          Presence({'id': 1, 'presence_id': '1'})
        ]
      });
      final stateBefore = state.deepClone();

      RealtimePresence.syncState(state, newState);

      expect(state.presences, stateBefore.presences);

      state = RealtimePresence.syncState(state, newState);

      expect(state.presences.keys, newState.presences.keys);
      expect(state.presences.values, state.presences.values);
    });

    test('onJoins new presences and onLeave\'s left presences', () {
      var state = PresenceState({
        'u4': [
          Presence({'id': 4, 'presence_id': '4'}),
        ]
      });

      final rawState = Fixtures.rawState();
      final joined = {};
      final left = {};
      void onJoin(String? key, current, newPres) {
        joined[key] = {
          'current': current,
          'newPres': newPres
              .map((m) => {'presence_id': m.presenceId, 'id': m.payload['id']})
        };
      }

      void onLeave(String? key, current, leftPres) {
        left[key] = {
          'current': current,
          'leftPres': leftPres
              .map((m) => {'presence_id': m.presenceId, 'id': m.payload['id']})
        };
      }

      state = RealtimePresence.syncState(state, rawState, onJoin, onLeave);

      final transformedState = Fixtures.transformedState();
      expect(state.toMap(), transformedState.toMap());
      expect(joined, {
        'u1': {
          'current': null,
          'newPres': [
            {'id': 1, 'presence_id': '1'}
          ]
        },
        'u2': {
          'current': null,
          'newPres': [
            {'id': 2, 'presence_id': '2'}
          ]
        },
        'u3': {
          'current': null,
          'newPres': [
            {'id': 3, 'presence_id': '3'}
          ]
        },
      });
      expect(left, {
        'u4': {
          'current': [],
          'leftPres': [
            {'id': 4, 'presence_id': '4'}
          ],
        },
      });
    });
  });
}
