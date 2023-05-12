# `realtime-dart`

> **Warning**
> This repository has been moved to the [supabase-flutter repo](https://github.com/supabase/supabase-flutter/tree/main/packages/realtime_client).

Listens to changes in a PostgreSQL Database and via websockets.

A dart client for Supabase [Realtime](https://github.com/supabase/realtime) server.

## Usage

### Creating a Socket connection

You can set up one connection to be used across the whole app.

```dart
import 'package:realtime_client/realtime_client.dart';

var client = RealtimeClient(REALTIME_URL);
client.connect();
```

**Socket Hooks**

```dart
client.onOpen(() => print('Socket opened.'));
client.onClose((event) => print('Socket closed $event'));
client.onError((error) => print('Socket error: $error'));
```

**Disconnect the socket**

Call `disconnect()` on the socket:

```dart
client.disconnect()
```

## Credits

- https://github.com/supabase/realtime-js - ported from realtime-js library

## License

This repo is licensed under MIT.
