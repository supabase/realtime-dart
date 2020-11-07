import 'package:realtime/realtime.dart';

/// Example to use with Supabase Realtime https://supabase.io/
void main() async {
  final socket = Socket('ws://SUPABASE_API_ENDPOINT/realtime/v1',
      params: {'apikey': 'SUPABSE_API_KEY'}, logger: (kind, msg, data) => {print('$kind $msg $data')});
  final channel = socket.channel('realtime:*');

  socket.onMessage((message) => print('MESSAGE $message'));

  socket.connect();
  channel.subscribe();

  // on unsubscribe and disconnect
  // channel.unsubscribe();
  // socket.disconnect();
}
