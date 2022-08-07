import 'package:realtime_client/src/realtime_channel.dart';

class Presence {
  final String presenceId;
  final Map<String, dynamic> payload;

  Presence(Map<String, dynamic> map)
      : presenceId = map['presence_id'],
        payload = map..remove('presence_id');

  Presence deepClone() {
    return Presence({'presence_id': presenceId, ...payload});
  }
}

class PresenceState {
  final Map<String, List<Presence>> presences;

  PresenceState(this.presences);

  PresenceState deepClone() {
    return PresenceState(
      presences,
    );
  }

  List<String> get keys {
    return presences.keys.toList();
  }
}

class PresenceDiff {
  final PresenceState joins;
  final PresenceState leaves;

  PresenceDiff({
    required this.joins,
    required this.leaves,
  });
}

class RawPresenceState {
  final Map<String, Map<String, List<Map<String, dynamic>>>> presences;

  RawPresenceState(this.presences);
}

class RawPresenceDiff {
  final RawPresenceState joins;
  final RawPresenceState leaves;

  RawPresenceDiff({required this.joins, required this.leaves});
}

typedef PresenceOnJoinCallback = void Function(
    String? key, dynamic currentPresence, dynamic newPresence);

typedef PresenceOnLeaveCallback = void Function(
    String? key, dynamic currentPresence, dynamic newPresence);

class PresenceOpts {
  final PresenceEvents events;

  PresenceOpts({required this.events});
}

class PresenceEvents {
  final String state;
  final String diff;

  PresenceEvents({required this.state, required this.diff});
}

typedef PresenceChooser<T> = T Function(String key, dynamic presence);

class RealtimePresence {
  PresenceState state = PresenceState({});
  List<RawPresenceDiff> pendingDiffs = [];
  String? joinRef;
  Map<String, dynamic> caller = {
    'onJoin': () {},
    'onLeave': () {},
    'onSync': () {}
  };

  /// Initializes the Presence
  ///
  /// [channel] - The RealtimeChannel
  /// [opts] - The options, for example `PresenceOpts(events: PresenceEvents(state: 'state', diff: 'diff'))`
  RealtimePresence(RealtimeChannel channel, [PresenceOpts? opts]) {
    final events = opts?.events ??
        PresenceEvents(state: 'presence_state', diff: 'presence_diff');

    channel.on(events.state, {}, (newState, [ref]) {
      final onJoin = caller['onJoin'];
      final onLeave = caller['onLeave'];
      final onSync = caller['onSync'];

      joinRef = channel.joinRef;

      state = RealtimePresence.syncState(
        state,
        newState,
        onJoin,
        onLeave,
      );

      for (final diff in pendingDiffs) {
        state = RealtimePresence.syncDiff(
          state,
          diff,
          onJoin,
          onLeave,
        );
      }

      pendingDiffs = [];

      onSync();
    });

    channel.on(events.diff, {}, (diff, [ref]) {
      final onJoin = caller['onJoin'];
      final onLeave = caller['onLeave'];
      final onSync = caller['onSync'];

      if (inPendingSyncState()) {
        pendingDiffs.add(diff);
      } else {
        state = RealtimePresence.syncDiff(
          state,
          diff,
          onJoin,
          onLeave,
        );

        onSync();
      }
    });
  }

  /// Used to sync the list of presences on the server with the
  /// client's state.
  ///
  /// An optional `onJoin` and `onLeave` callback can be provided to
  /// react to changes in the client's local presences across
  /// disconnects and reconnects with the server.
  static PresenceState syncState(
    PresenceState currentState,
    dynamic newState, [
    PresenceOnJoinCallback? onJoin,
    PresenceOnLeaveCallback? onLeave,
  ]) {
    final state = currentState.deepClone();
    final transformedState = _transformState(newState);
    final PresenceState joins = PresenceState({});
    final PresenceState leaves = PresenceState({});

    _map(state, (key, presence) {
      if (!transformedState.presences.containsKey(key)) {
        leaves.presences[key] = presence;
      }
    });

    _map(transformedState, (key, newPresences) {
      final currentPresences = state.presences[key];

      if (currentPresences != null) {
        final newPresenceIds = newPresences.map((m) => m.presenceId).toList();
        final curPresenceIds =
            currentPresences.map((m) => m.presenceId).toList();
        final joinedPresences = newPresences
            .where((m) => !curPresenceIds.contains(m.presenceId))
            .toList();
        final leftPresences = currentPresences
            .where((m) => !newPresenceIds.contains(m.presenceId))
            .toList();

        if (joinedPresences.isNotEmpty) {
          joins.presences[key] = joinedPresences;
        }

        if (leftPresences.isNotEmpty) {
          leaves.presences[key] = leftPresences;
        }
      } else {
        joins.presences[key] = newPresences;
      }
    });

    return syncDiff(
        state, PresenceDiff(joins: joins, leaves: leaves), onJoin, onLeave);
  }

  /// Used to sync a diff of presence join and leave events from the
  /// server, as they happen.
  ///
  /// Like `syncState`, `syncDiff` accepts optional `onJoin` and
  /// `onLeave` callbacks to react to a user joining or leaving from a
  /// device.
  static PresenceState syncDiff(PresenceState state, dynamic diff,
      [PresenceOnJoinCallback? onJoin, PresenceOnLeaveCallback? onLeave]) {
    assert(diff is RawPresenceDiff || diff is PresenceDiff,
        'diff must be RawPresenceDiff or RawPresenceDiff');
    final joins = _transformState(diff.joins);
    final leaves = _transformState(diff.leaves);

    onJoin ??= (_, __, ___) => {};

    onLeave ??= (_, __, ___) => {};

    _map(joins, (key, newPresences) {
      final currentPresences = state.presences[key];
      state.presences[key] = (newPresences as List).map((presence) {
        return presence.deepClone() as Presence;
      }).toList();

      if (currentPresences != null) {
        final joinedPresenceIds =
            state.presences[key]!.map((m) => m.presenceId).toList();
        final curPresences = currentPresences
            .where((m) => !joinedPresenceIds.contains(m.presenceId))
            .toList();

        state.presences[key]!.insertAll(0, curPresences);
      }

      onJoin!(key, currentPresences, newPresences);
    });

    _map(leaves, (key, leftPresences) {
      var currentPresences = state.presences[key];

      if (currentPresences == null) return;

      final presenceIdsToRemove =
          leftPresences.map((leftPresence) => leftPresence.presenceId).toList();

      currentPresences = currentPresences
          .where(
              (presence) => !presenceIdsToRemove.contains(presence.presenceId))
          .toList();

      state.presences[key] = currentPresences;

      onLeave!(key, currentPresences, leftPresences);

      if (currentPresences.isEmpty) {
        state.presences.remove(key);
      }
    });

    return state;
  }

  static List<T> _map<T>(PresenceState obj, PresenceChooser<T> func) {
    return obj.keys.map((key) => func(key, obj.presences[key]!)).toList();
  }

  /// Returns the array of presences, with selected metadata.
  static List<T> listAll<T>(PresenceState presences,
      [PresenceChooser<T>? chooser]) {
    chooser ??= (key, pres) => pres;

    return _map(presences, (key, presences) => chooser!(key, presences));
  }

  /// Remove 'metas' key
  /// Change 'phx_ref' to 'presence_id'
  /// Remove 'phx_ref' and 'phx_ref_prev'
  ///
  /// @example
  /// // returns {
  ///  abc123: [
  ///    { presence_id: '2', user_id: 1 },
  ///    { presence_id: '3', user_id: 2 }
  ///  ]
  /// }
  /// RealtimePresence.transformState({
  ///  abc123: {
  ///    metas: [
  ///      { phx_ref: '2', phx_ref_prev: '1' user_id: 1 },
  ///      { phx_ref: '3', user_id: 2 }
  ///    ]
  ///  }
  /// })
  static PresenceState _transformState(dynamic state) {
    assert(state is PresenceState || state is RawPresenceState,
        'state must be a PresenceState or RawPresenceState');

    final Map<String, List<Presence>> newStateMap = {};

    for (final key in (state.presences as Map<String, dynamic>).keys) {
      final presences = state.presences[key]!;

      if (state is RawPresenceState) {
        newStateMap[key] =
            (presences['metas'] as List).map<Presence>((presence) {
          presence['presence_id'] = presence['phx_ref'] as String;

          presence.remove('phx_ref');
          presence.remove('phx_ref_prev');

          return Presence(presence);
        }).toList();
      } else {
        newStateMap[key] = presences;
      }
    }
    return PresenceState(newStateMap);
  }

  void onJoin(PresenceOnJoinCallback callback) {
    caller['onJoin'] = callback;
  }

  void onLeave(PresenceOnLeaveCallback callback) {
    caller['onLeave'] = callback;
  }

  void onSync(void Function() callback) {
    caller['onSync'] = callback;
  }

  List<T> list<T>([PresenceChooser<T>? by]) {
    return RealtimePresence.listAll<T>(state, by);
  }

  bool inPendingSyncState() {
    return true;
  }
}
