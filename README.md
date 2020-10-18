# Realtime Client

Listens to changes in a PostgreSQL Database and via websockets.

This is for usage with Supabase [Realtime](https://github.com/supabase/realtime) server.

Pre-release verion! This repo is still under heavy development and the documentation is evolving. You're welcome to try it, but expect some breaking changes.

## Usage

### Creating a Socket connection

You can set up one connection to be used across the whole app.

```dart
import 'package:realtime/realtime.dart';

var socket = Socket(REALTIME_URL);
socket.connect();
```

**Socket Hooks**

```dart
socket.onOpen(() => print('Socket opened.'));
socket.onClose(() => print('Socket closed.'));
socket.onError((e) => print('Socket error ${e.message}'));
```

## Credits

- https://github.com/supabase/realtime-js - ported from realtime-js library

## License

This repo is liscenced under MIT.
