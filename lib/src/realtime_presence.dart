import 'package:realtime_client/src/realtime_channel.dart';

class Presence {
  final String presenceId;
  final Map<String, dynamic> payload;

  Presence({required this.presenceId, required this.payload});
}

class PresenceState {
  final Map<String, List<Presence>> state;

  PresenceState(this.state);
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
    // final state = c
    return currentState;
  }

  static PresenceState syncDiff(
      PresenceState state, dynamic diff, dynamic onJoin, dynamic onLeave) {
    return state;
  }

  bool inPendingSyncState() {
    return true;
  }
}
