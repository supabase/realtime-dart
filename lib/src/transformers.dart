// Adapted from epgsql (src/epgsql_binary.erl), this module licensed under
// 3-clause BSD found here: https://raw.githubusercontent.com/epgsql/epgsql/devel/LICENSE

import 'dart:convert';
import 'package:collection/collection.dart' show IterableExtension;

enum PostgresTypes {
  abstime,
  bool,
  date,
  daterange,
  float4,
  float8,
  int2,
  int4,
  int4range,
  int8,
  int8range,
  json,
  jsonb,
  money,
  numeric,
  oid,
  reltime,
  time,
  timestamp,
  timestamptz,
  timetz,
  tsrange,
  tstzrange,
}

class Column {
  /// any special flags for the column. eg: ["key"]
  List<String> flags;

  /// the column name. eg: "user_id"
  String name;

  /// the column type. eg: "uuid"
  String type;

  /// the type modifier. eg: 4294967295
  int? typeModifier;

  Column(this.name, this.type, {this.flags = const [], this.typeModifier});
}

/// Takes an array of columns and an object of string values then converts each string value
/// to its mapped type.
///
/// `columns` All of the columns
/// `records` The map of string values
/// `skipTypes` The array of types that should not be converted
///
/// ```dart
/// convertChangeData([{name: 'first_name', type: 'text'}, {name: 'age', type: 'int4'}], {first_name: 'Paul', age:'33'}, {})
/// => { first_name: 'Paul', age: 33 }
/// ```
Map convertChangeData(
    List<Map<String, dynamic>> columns, Map<String, dynamic> records,
    {List<String>? skipTypes}) {
  final result = <String, dynamic>{};
  final _skipTypes = skipTypes ?? [];
  final parsedColumns = <Column>[];

  for (final element in columns) {
    final name = element['name'] as String?;
    final type = element['type'] as String?;
    if (name != null && type != null) parsedColumns.add(Column(name, type));
  }

  records.forEach((key, value) {
    result[key] = convertColumn(key, parsedColumns, records, _skipTypes);
  });
  return result;
}

/// Converts the value of an individual column.
///
/// `columnName` The column that you want to convert
/// `columns` All of the columns
/// `records` The map of string values
/// `skipTypes` An array of types that should not be converted
///
/// ```dart
/// convertColumn('age', [{name: 'first_name', type: 'text'}, {name: 'age', type: 'int4'}], ['Paul', '33'], [])
/// => 33
/// convertColumn('age', [{name: 'first_name', type: 'text'}, {name: 'age', type: 'int4'}], ['Paul', '33'], ['int4'])
/// => "33"
/// ```
dynamic convertColumn(String columnName, List<Column> columns,
    Map<String, dynamic> records, List<String> skipTypes) {
  final column = columns.firstWhereOrNull((x) => x.name == columnName);
  final columnValue = records[columnName];
  final columnValueStr = columnValue == null
      ? null
      : columnValue is String
          ? columnValue
          : columnValue.toString();

  if (column == null || skipTypes.contains(column.type)) {
    return noop(columnValueStr);
  } else {
    return convertCell(column.type, columnValueStr);
  }
}

/// If the value of the cell is `null`, returns null.
/// Otherwise converts the string value to the correct type.
///
/// `type` A postgres column type
/// `stringValue` The cell value
///
/// ```dart
/// @example convertCell('bool', 'true')
/// => true
/// @example convertCell('int8', '10')
/// => 10
/// @example convertCell('_int4', '{1,2,3,4}')
/// => [1,2,3,4]
/// ```
dynamic convertCell(String type, String? stringValue) {
  try {
    if (stringValue == null) return null;

    // if data type is an array
    if (type[0] == '_') {
      final arrayValue = type.substring(1, type.length);
      return toArray(stringValue, arrayValue);
    }

    final typeEnum = PostgresTypes.values
        .firstWhereOrNull((e) => e.toString() == 'PostgresTypes.$type');
    // If not null, convert to correct type.
    switch (typeEnum) {
      case PostgresTypes.abstime:
        return noop(stringValue); // To allow users to cast it based on Timezone
      case PostgresTypes.bool:
        return toBoolean(stringValue);
      case PostgresTypes.date:
        return noop(stringValue); // To allow users to cast it based on Timezone
      case PostgresTypes.daterange:
        return toDateRange(stringValue);
      case PostgresTypes.float4:
        return toDouble(stringValue);
      case PostgresTypes.float8:
        return toDouble(stringValue);
      case PostgresTypes.int2:
        return toInt(stringValue);
      case PostgresTypes.int4:
        return toInt(stringValue);
      case PostgresTypes.int4range:
        return toIntRange(stringValue);
      case PostgresTypes.int8:
        return toInt(stringValue);
      case PostgresTypes.int8range:
        return toIntRange(stringValue);
      case PostgresTypes.json:
        return toJson(stringValue);
      case PostgresTypes.jsonb:
        return toJson(stringValue);
      case PostgresTypes.money:
        return toDouble(stringValue);
      case PostgresTypes.numeric:
        return toDouble(stringValue);
      case PostgresTypes.oid:
        return toInt(stringValue);
      case PostgresTypes.reltime:
        return noop(stringValue); // To allow users to cast it based on Timezone
      case PostgresTypes.time:
        return noop(stringValue); // To allow users to cast it based on Timezone
      case PostgresTypes.timestamp:
        return toTimestampString(stringValue); // Tobe consistent with PostgREST
      case PostgresTypes.timestamptz:
        return noop(stringValue); // To allow users to cast it based on Timezone
      case PostgresTypes.timetz:
        return noop(stringValue); // To allow users to cast it based on Timezone
      case PostgresTypes.tsrange:
        return toDateRange(stringValue);
      case PostgresTypes.tstzrange:
        return toDateRange(stringValue);
      default:
        // All the rest will be returned as strings
        return noop(stringValue);
    }
  } catch (error) {
    //print('Could not convert cell of type $type and value $stringValue');
    //print('This is the error: $error');
    return stringValue;
  }
}

/// Converts a Postgres Array into a native JS array
///
///``` dart
/// @example toArray('{1,2,3,4}', 'int4')
/// //=> [1,2,3,4]
/// @example toArray('{}', 'int4')
/// //=> []
///  ```
List<dynamic> toArray(String type, String stringValue) {
  // this takes off the '{' & '}'
  final stringEnriched = stringValue.substring(1, stringValue.length - 1);

  // converts the string into an array
  // if string is empty (meaning the array was empty), an empty array will be immediately returned
  final stringArray =
      stringEnriched.isNotEmpty ? stringEnriched.split(',') : <String>[];
  final array = stringArray.map((string) => convertCell(type, string)).toList();
  return array;
}

/// Fixes timestamp to be ISO-8601. Swaps the space between the date and time for a 'T'
/// See https://github.com/supabase/supabase/issues/18
///
///```dart
/// @example toTimestampString('2019-09-10 00:00:00')
/// => '2019-09-10T00:00:00'
/// ```
String toTimestampString(String stringValue) {
  return stringValue.replaceAll(' ', 'T');
}

String? noop(String? stringValue) {
  return stringValue;
}

bool? toBoolean(String? stringValue) {
  switch (stringValue) {
    case 't':
      return true;
    case 'f':
      return false;
    default:
      return null;
  }
}

DateTime toDate(String stringValue) {
  return DateTime.parse(stringValue);
}

List<DateTime> toDateRange(String stringValue) {
  final arr = json.decode(stringValue);
  return [DateTime.parse(arr[0] as String), DateTime.parse(arr[1] as String)];
}

double toDouble(String stringValue) {
  return double.parse(stringValue);
}

int toInt(String stringValue) {
  return int.parse(stringValue);
}

List<int> toIntRange(String stringValue) {
  final arr = json.decode(stringValue);
  return [int.parse(arr[0] as String), int.parse(arr[1] as String)];
}

dynamic toJson(String stringValue) {
  return json.decode(stringValue);
}
