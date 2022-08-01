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

extension on Presence {
  Map toMap() {
    return {
      'presence_id': presenceId,
      ...payload,
    };
  }
}

extension on RawPresenceState {
  RawPresenceState cloneDeep() {
    return RawPresenceState(presences);
  }
}

class Fixtures {
  static RawPresenceState joins() {
    return RawPresenceState({
      'u1': {
        'metas': [
          {'id': 1, 'phx_ref': '1.2'}
        ]
      }
    });
  }

  static RawPresenceState leaves() {
    return RawPresenceState({
      'u2': {
        'metas': [
          {'id': 2, 'phx_ref': '2'}
        ]
      }
    });
  }

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

    test('onJoins only newly added presences', () {
      var state = PresenceState({
        'u3': [
          Presence({'id': 3, 'presence_id': '3'})
        ]
      });
      final rawState = RawPresenceState({
        'u3': {
          'metas': [
            {'id': 3, 'phx_ref': '3'},
            {'id': 3, 'phx_ref': '3.new'},
          ],
        },
      });

      final joined = [];
      final left = [];
      void onJoin(key, current, newPres) {
        joined.add({
          key: {
            'current': current.map((m) => (m as Presence).toMap()).toList(),
            'newPres': newPres.map((m) => (m as Presence).toMap()).toList()
          }
        });
      }

      void onLeave(key, current, leftPres) {
        joined.add({
          key: {
            'current': current.map((m) => (m as Presence).toMap()).toList(),
            'leftPres': leftPres.map((m) => (m as Presence).toMap()).toList()
          }
        });
      }

      state = RealtimePresence.syncState(
          state, rawState.cloneDeep(), onJoin, onLeave);
      expect(state.toMap(), {
        'u3': [
          {'id': 3, 'presence_id': '3'},
          {'id': 3, 'presence_id': '3.new'},
        ],
      });

      expect(joined, [
        {
          'u3': {
            'current': [
              {'id': 3, 'presence_id': '3'}
            ],
            'newPres': [
              {'id': 3, 'presence_id': '3.new'}
            ],
          }
        }
      ]);

      expect(left, []);
    });
  });

  group('syncDiff', () {
    test('syncs empty state', () {
      final joins = PresenceState({
        'u1': [
          Presence({'id': 1, 'phx_ref': '1', 'presence_id': '1'})
        ]
      });
      final state = RealtimePresence.syncDiff(
        PresenceState({}),
        PresenceDiff(
          joins: joins,
          leaves: PresenceState({}),
        ),
      );
      expect(state.toMap(), joins.toMap());
    });

    test('removes presences when empty and adds additional presences', () {
      var state = Fixtures.transformedState();
      state = RealtimePresence.syncDiff(state,
          RawPresenceDiff(joins: Fixtures.joins(), leaves: Fixtures.leaves()));

      expect(
          state.toMap(),
          PresenceState({
            'u1': [
              Presence({'id': 1, 'presence_id': '1'}),
              Presence({'id': 1, 'presence_id': '1.2'}),
            ],
            'u3': [
              Presence({'id': 3, 'presence_id': '3'})
            ],
          }).toMap());
    });

    test('removes presence while leaving key if other presences exist', () {
      var state = PresenceState({
        'u1': [
          Presence({'id': 1, 'presence_id': '1'}),
          Presence({'id': 1, 'presence_id': '1.2'}),
        ],
      });
      state = RealtimePresence.syncDiff(
          state,
          RawPresenceDiff(
            joins: RawPresenceState({}),
            leaves: RawPresenceState(
              {
                'u1': {
                  'metas': [
                    {'id': 1, 'phx_ref': '1'}
                  ]
                }
              },
            ),
          ));

      expect(
          state.toMap(),
          PresenceState({
            'u1': [
              Presence({'id': 1, 'presence_id': '1.2'})
            ],
          }).toMap());
    });

    group('list', () {
      //      it('lists full presence by default', function () {
      //   const state = fixtures.transformedState()

      //   assert.deepEqual(RealtimePresence.list(state), [
      //     [{ id: 1, presence_id: '1' }],
      //     [{ id: 2, presence_id: '2' }],
      //     [{ id: 3, presence_id: '3' }],
      //   ])
      // })

      test('lists full presence by default', () {
        final state = Fixtures.transformedState();

        expect(
            RealtimePresence.listAll(state)
                .map((e) => e.map((e) => (e as Presence).toMap()).toList())
                .toList(),
            [
              [
                Presence({'id': 1, 'presence_id': '1'}).toMap()
              ],
              [
                Presence({'id': 2, 'presence_id': '2'}).toMap()
              ],
              [
                Presence({'id': 3, 'presence_id': '3'}).toMap()
              ],
            ]);
      });

      test('lists with custom function', () {
        final state = PresenceState({
          'u1': [
            Presence({'id': 1, 'presence_id': '1.first'}),
            Presence({'id': 1, 'presence_id': '1.second'}),
          ],
        });

        dynamic listBy(key, list) {
          return list.first;
        }

        expect(
            RealtimePresence.listAll(state, listBy)
                .map((e) => (e as Presence).toMap()),
            [
              {'id': 1, 'presence_id': '1.first'},
            ]);
      });
    });
  });
}
