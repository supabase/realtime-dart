# Realtime Client

Listens to changes in a PostgreSQL Database and via websockets.

This is for usage with Supabase [Realtime](https://github.com/supabase/realtime) server.

[![pub package](https://img.shields.io/pub/v/realtime_client.svg)](https://pub.dev/packages/realtime_client)
[![pub test](https://github.com/supabase/realtime-dart/workflows/Test/badge.svg)](https://github.com/supabase/realtime-dart/actions?query=workflow%3ATest)

**Pre-release verion! This repo is still under heavy development and the documentation is evolving.**
You're welcome to try it, but expect some breaking changes.

## Usage

### Creating a Socket connection

You can set up one connection to be used across the whole app.

```dart
import 'package:realtime_client/realtime_client.dart';

var client = Socket(REALTIME_URL);
client.connect();
```

**Socket Hooks**

```dart
client.onOpen(() => print('Socket opened.'));
client.onClose((event) => print('Socket closed $event'));
client.onError((error) => print('Socket error: $error'));
```

### Subscribing to events

You can listen to `INSERT`, `UPDATE`, `DELETE`, or all `*` events.

You can subscribe to events on the whole database, schema, table, or individual columns using `channel()`. Channels are multiplexed over the Socket connection. 

To join a channel, you must provide the `topic`, where a topic is either:

- `realtime` - entire database
- `realtime:{schema}` - where `{schema}` is the Postgres Schema
- `realtime:{schema}:{table}` - where `{table}` is the Postgres table name
- `realtime:{schema}:{table}:{col}.eq.{val}` - where `{col}` is the column name, and `{val}` is the value which you want to match

**Examples**

```dart
// Listen to events on the entire database.
final databaseChanges = client.channel('realtime:*');
databaseChanges.on('*', (e, {ref}) => print(e) );
databaseChanges.on('INSERT', (e, {ref}) => print(e) );
databaseChanges.on('UPDATE', (e, {ref}) => print(e) );
databaseChanges.on('DELETE', (e, {ref}) => print(e) );
databaseChanges.subscribe()

// Listen to events on a schema, using the format `realtime:{SCHEMA}`
var publicSchema = client.channel('realtime:public');
publicSchema.on('*', (e, {ref}) => print(e) );
publicSchema.on('INSERT', (e, {ref}) => print(e) );
publicSchema.on('UPDATE', (e, {ref}) => print(e) );
publicSchema.on('DELETE', (e, {ref}) => print(e) );
publicSchema.subscribe();

// Listen to events on a table, using the format `realtime:{SCHEMA}:{TABLE}`
var usersTable = client.channel('realtime:public:users');
usersTable.on('*', (e, {ref}) => print(e) );
usersTable.on('INSERT', (e, {ref}) => print(e) );
usersTable.on('UPDATE', (e, {ref}) => print(e) );
usersTable.on('DELETE', (e, {ref}) => print(e) );
usersTable.subscribe();

// Listen to events on a row, using the format `realtime:{SCHEMA}:{TABLE}:{COL}.eq.{VAL}`
var rowChanges = client.channel('realtime:public:users:id.eq.1');
rowChanges.on('*', (e, {ref}) => print(e) );
rowChanges.on('INSERT', (e, {ref}) => print(e) );
rowChanges.on('UPDATE', (e, {ref}) => print(e) );
rowChanges.on('DELETE', (e, {ref}) => print(e) );
rowChanges.subscribe();
```

**Removing a subscription**

You can unsubscribe from a topic using `channel.unsubscribe()`.

**Disconnect the socket**

Call `disconnect()` on the socket:

```dart
client.disconnect()
```

**Duplicate Join Subscriptions**

While the client may join any number of topics on any number of channels, the client may only hold a single subscription for each unique topic at any given time. When attempting to create a duplicate subscription, the server will close the existing channel, log a warning, and spawn a new channel for the topic. The client will have their `channel.onClose` callbacks fired for the existing channel, and the new
channel join will have its receive hooks processed as normal.

**Channel Hooks**

```dart
channel.onError( (e) => print("there was an error $e") );
channel.onClose( () => print("the channel has gone away gracefully") );
```

- `onError` hooks are invoked if the socket connection drops, or the channel crashes on the server. In either case, a channel rejoin is attempted automatically in an exponential backoff manner.
- `onClose` hooks are invoked only in two cases. 1) the channel explicitly closed on the server, or 2). The client explicitly closed, by calling `channel.unsubscribe()`

## Credits

- https://github.com/supabase/realtime-js - ported from realtime-js library

## License

This repo is liscenced under MIT.
