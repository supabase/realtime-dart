class Presence {
  final String presenceId;
  final Map<String, dynamic> other;

  Presence(this.presenceId, this.other);
}

class PresenceState {
  final List<Presence> presenses;

  PresenceState(this.presenses);
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
  final Map<String, Record> some;

  RawPresenceState(this.some);
}

class Record {
  Record(this.metas);
  final Map<String, dynamic> metas;
}

// type RawPresenceState = {
//   [key: string]: Record<
//     'metas',
//     {
//       phx_ref?: string
//       phx_ref_prev?: string
//       [key: string]: any
//     }[]
//   >
// }

class RawPresenceDiff {
  final RawPresenceState joins;
  final RawPresenceState leaves;

  RawPresenceDiff(this.joins, this.leaves);
}

typedef PresenceChooser<T> = T Function(String key, dynamic presence);
