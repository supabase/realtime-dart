const String VSN = '1.0.0';
const int DEFAULT_TIMEOUT = 10000;
const int WS_CLOSE_NORMAL = 1000;

class SOCKET_STATES {
  static int get connecting => 0;
  static int get open => 1;
  static int get closing => 2;
  static int get closed => 3;
}

class CHANNEL_STATES {
  static String get closed => 'closed';
  static String get errored => 'errored';
  static String get joined => 'joined';
  static String get joining => 'joining';
  static String get leaving => 'leaving';
}

class CHANNEL_EVENTS {
  static String get close => 'phx_close';
  static String get error => 'phx_error';
  static String get join => 'phx_join';
  static String get reply => 'phx_reply';
  static String get leave => 'phx_leave';
}

class TRANSPORTS {
  static String get websocket => 'websocket';
}
