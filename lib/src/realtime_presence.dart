import 'package:realtime_client/src/realtime_channel.dart';

class Presence {
  final String presenceId;
  final Map<String, dynamic> payload;

  Presence({required this.presenceId, required this.payload});
}

class PresenceState {
  final Map<String, List<Presence>> state;

  PresenceState(this.state);

  PresenceState copyWith({
    Map<String, List<Presence>>? state,
  }) {
    return PresenceState(
      state ?? this.state,
    );
  }

  List<String> get keys {
    return state.keys.toList();
  }
}

class RawPresenceState {
  final Map<String, List<dynamic>> state;

  RawPresenceState(this.state);
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

typedef PresenceChooser<T> = T Function(String key, List<Presence> presence);

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

    channel.on(events.state, {}, (newState, {ref}) {
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

    channel.on(events.diff, {}, (diff, {ref}) {
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
  static PresenceState syncState(PresenceState currentState, dynamic newState,
      PresenceOnJoinCallback onJoin, PresenceOnLeaveCallback onLeave) {
    final state = currentState.copyWith();
    final transformedState = _transformState(state);
    final PresenceState joins = PresenceState({});
    final PresenceState leaves = PresenceState({});

    _map(state, (key, presence) {
      if (!transformedState.state.containsKey(key)) {
        leaves.state[key] = presence;
      }
    });

    _map(transformedState, (key, presence) {
      final newPresences = presence;
      final currentPresences = state.state[key];

      if (currentPresences != null) {
        final newPresenceIds = newPresences.map((m) => m.presenceId).toList();
        final curPresenceIds =
            currentPresences.map((m) => m.presenceId).toList();
        final joinedPresences = newPresences
            .where((m) => curPresenceIds.contains(m.presenceId))
            .toList();
        final leftPresences = currentPresences
            .where((m) => newPresenceIds.contains(m.presenceId))
            .toList();

        if (joinedPresences.isNotEmpty) {
          joins.state[key] = joinedPresences;
        }

        if (leftPresences.isNotEmpty) {
          leaves.state[key] = leftPresences;
        }
      } else {
        joins.state[key] = newPresences;
      }

      return syncDiff(state, {joins, leaves}, onJoin, onLeave);
    });

    return currentState;
  }

  static PresenceState syncDiff(
      PresenceState state, dynamic diff, dynamic onJoin, dynamic onLeave) {
    return state;
  }

  static PresenceState _transformState(dynamic state) {
    assert(state is PresenceState || state is RawPresenceState,
        'state must be a PresenceState or RawPresenceState');

    final Map<String, List<Presence>> newState = {};
    for (final key in (state.state as Map<String, dynamic>).keys) {
      final presences = state[key];

      if ((presences.keys as List).contains('metas')) {
        newState[key] = (presences['metas'] as List).map<Presence>((presence) {
          final presenceId = presence['phx_ref'] as String;

          presence.remove('phx_ref');
          presence.remove('phx_ref_prev');

          return Presence(presenceId: presenceId, payload: presence);
        }).toList();
      } else {
        newState[key] = presences;
      }
    }
    return PresenceState(newState);
  }

  static List<T> _map<T>(PresenceState obj, PresenceChooser<T> func) {
    return obj.keys.map((key) => func(key, obj.state[key]!)).toList();
  }

  bool inPendingSyncState() {
    return true;
  }
}
