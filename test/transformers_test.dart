import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main() {
  test('transformers toArray', () {
    expect(toArray('int4', '{}'), equals([]));
    expect(toArray('int4', '{1}'), equals([1]));
    expect(toArray('int4', '{1,2,3}'), equals([1, 2, 3]));
  });

  test('transformers toTimestampString', () {
    expect(toTimestampString('2020-10-30 12:34:56'),
        equals('2020-10-30T12:34:56'));
  });

  test('transformers toBoolean', () {
    expect(toBoolean('t'), isTrue);
    expect(toBoolean('f'), isFalse);
    expect(toBoolean('abc'), isNull);
    expect(toBoolean(null), isNull);
    expect(toBoolean(''), isNull);
  });

  test('transformers noop', () {
    expect(noop(null), equals(null));
    expect(noop(''), equals(''));
    expect(noop('abc'), equals('abc'));
  });

  test('transformers toDateRange', () {
    expect(
        toDateRange('["2020-10-30 12:34:56", "2020-11-01 01:23:45"]'),
        equals([
          DateTime(2020, 10, 30, 12, 34, 56),
          DateTime(2020, 11, 1, 1, 23, 45)
        ]));
  });

  test('transformers convertChangeData', () {
    final columns = [{'name': 'first_name', 'type': 'text'}, {'name': 'age', 'type': 'int4'}];
    final records = {'first_name': 'Paul', 'age':'33'};
    expect(convertChangeData(columns, records), { 'first_name': 'Paul', 'age': 33 });
  });
}
