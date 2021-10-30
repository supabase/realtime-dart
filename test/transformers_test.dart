import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main() {
  test('transformers toTimestampString', () {
    expect(
      toTimestampString('2020-10-30 12:34:56'),
      equals('2020-10-30T12:34:56'),
    );
  });

  test('transformers toBoolean', () {
    expect(toBoolean('t'), isTrue);
    expect(toBoolean('f'), isFalse);
    expect(toBoolean('abc'), throwsException);
    expect(toBoolean(null), isNull);
    expect(toBoolean(''), throwsException);
  });

  test('transformers noop', () {
    expect(noop(null), equals(null));
    expect(noop(''), equals(''));
    expect(noop('abc'), equals('abc'));
  });

  group('transformers convertChangeData', () {
    test('with basic usecase', () {
      final columns = [
        {
          'flags': ['key'],
          'name': 'id',
          'type': 'int8',
          'type_modifier': 4294967295
        },
        {
          'flags': [],
          'name': 'name',
          'type': 'text',
          'type_modifier': 4294967295
        },
        {
          'flags': [],
          'name': 'continent',
          'type': 'continents',
          'type_modifier': 4294967295
        }
      ];
      final records = {'id': '253', 'name': 'Singapore', 'continent': null};
      expect(
        convertChangeData(columns, records),
        equals({'id': 253, 'name': 'Singapore', 'continent': null}),
      );
    });

    test('with int in record value', () {
      final columns = [
        {
          'name': 'first_name',
          'type': 'text',
        },
        {
          'name': 'age',
          'type': 'int4',
        }
      ];
      final records = {'first_name': 'Mark', 'age': 23};
      expect(
        convertChangeData(columns, records),
        {'first_name': 'Mark', 'age': 23},
      );
    });

    test('with null in record value', () {
      final columns = [
        {
          'name': 'first_name',
          'type': 'text',
        },
        {
          'name': 'age',
          'type': 'int4',
        }
      ];
      final records = {'first_name': 'Paul', 'age': null};
      expect(
        convertChangeData(columns, records),
        {'first_name': 'Paul', 'age': null},
      );
    });
  });

  group('convertCell', () {
    test('bool', () {
      expect(convertCell('bool', 't'), isTrue);
      expect(convertCell('bool', true), isTrue);
    });

    test('int8', () {
      expect(convertCell('int8', '10'), 10);
      expect(convertCell('int8', 10), 10);
    });

    test('numeric', () {
      expect(convertCell('numeric', '12345.12345'), 12345.12345);
      expect(convertCell('numeric', 12345.12345), 12345.12345);
    });

    test('int4range', () {
      expect(convertCell('int4range', '[1,10)'), '[1,10)');
    });

    test('float8', () {
      expect(convertCell('float8', null), isNull);
    });

    test('json', () {
      expect(convertCell('json', '"[1,2,3]"'), equals('[1,2,3]'));
      expect(convertCell('json', '[1,2,3]'), equals([1, 2, 3]));
    });

    test('_int4', () {
      expect(convertCell('_int4', '{}'), equals([]));
      expect(convertCell('_int4', '{1}'), equals([1]));
      expect(convertCell('_int4', '{1,2,3}'), equals([1, 2, 3]));
    });

    test('_varchar', () {
      expect(convertCell('_varchar', '{}'), equals([]));
      expect(convertCell('_varchar', '{foo}'), equals(['foo']));
      expect(convertCell('_varchar', '{foo,bar}'), equals(['foo', 'bar']));
    });
  });

  test('transformers toArray', () {
    expect(toArray('{}', 'int4'), equals([]));
    expect(toArray('{1}', 'int4'), equals([1]));
    expect(toArray('{1,2,3}', 'int4'), equals([1, 2, 3]));
    expect(
      toArray(
        '{"[2021-01-01,2021-12-31)","(2021-01-01,2021-12-32]"}',
        'daterange',
      ),
      equals(['[2021-01-01,2021-12-31)', '(2021-01-01,2021-12-32]']),
    );
    expect(
      toArray([99, 999, 9999, 99999], 'int8'),
      equals([99, 999, 9999, 99999]),
    );
  });
}
