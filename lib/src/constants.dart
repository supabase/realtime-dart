import 'package:realtime_client/src/version.dart';

class Constants {
  static const String vsn = '1.0.0';
  static const Duration defaultTimeout = Duration(milliseconds: 10000);
  static const int wsCloseNormal = 1000;
  static const Map<String, String> defaultHeaders = {
    'X-Client-Info': 'realtime-dart/$version',
  };
}

enum SocketStates { connecting, open, closing, closed, disconnected }

enum ChannelStates { closed, errored, joined, joining, leaving }

enum ChannelEvents {
  close,
  error,
  join,
  reply,
  leave,
  heartbeat,
  accessToken,
  broadcast,
  presence,
  postgresChanges;

  static ChannelEvents fromName(String type) {
    for (ChannelEvents enumVariant in ChannelEvents.values) {
      if (enumVariant.name == type) return enumVariant;
    }
    throw 'No type $type exists';
  }
}

extension ChannelEventsName on ChannelEvents {
  String eventName() {
    if (this == ChannelEvents.accessToken) {
      return 'access_token';
    } else if (this == ChannelEvents.postgresChanges) {
      return 'postgres_changes';
    }
    return 'phx_$name';
  }
}

class Transports {
  static const String websocket = 'websocket';
}
