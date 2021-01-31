import 'package:realtime_client/realtime_client.dart';

/// Example to use with Supabase Realtime https://supabase.io/
// ignore: avoid_void_async
void main() async {
  final socket = RealtimeClient('ws://SUPABASE_API_ENDPOINT/realtime/v1',
      params: {'apikey': 'SUPABSE_API_KEY'},
      // ignore: avoid_print
      logger: (kind, msg, data) => {print('$kind $msg $data')});
  final channel = socket.channel('realtime:*');

  // ignore: avoid_print
  socket.onMessage((message) => print('MESSAGE $message'));

  socket.connect();
  channel.subscribe();

  // on unsubscribe and disconnect
  // channel.unsubscribe();
  // socket.disconnect();
}
