import 'package:realtime_client/realtime_client.dart';

/// Example to use with Supabase Realtime https://supabase.io/
void main() async {
  final socket = RealtimeClient('ws://SUPABASE_API_ENDPOINT/realtime/v1',
      params: {'apikey': 'SUPABSE_API_KEY'},
      // ignore: avoid_print
      logger: (kind, msg, data) => {print('$kind $msg $data')});

  final channel = socket.channel('realtime:public');
  channel.on('DELETE', (payload, {ref}) {
    print('channel delete payload: $payload');
  });
  channel.on('INSERT', (payload, {ref}) {
    print('channel insert payload: $payload');
  });

  socket.onMessage((message) => print('MESSAGE $message'));

  // on connect and subscribe
  socket.connect();
  channel.subscribe().receive('ok', (_) => print('SUBSCRIBED'));

  // on unsubscribe and disconnect
  channel.unsubscribe();
  socket.disconnect();
}
