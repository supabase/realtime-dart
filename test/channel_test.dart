import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main(){

  test('channel should be initially closed', (){
    final channel = Channel('topic', Socket('endpoint'));
    expect(channel.isClosed(), isTrue);
    channel.sendJoin(const Duration(seconds: 5));
    expect(channel.isJoining(), isTrue);
  });
}