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

class PostgresColumn {
  /// the column name. eg: "user_id"
  String name;

  /// the column type. eg: "uuid"
  String type;

  /// any special flags for the column. eg: ["key"]
  List<String>? flags;

  /// the type modifier. eg: 4294967295
  int? typeModifier;

  PostgresColumn(
    this.name,
    this.type, {
    this.flags = const [],
    this.typeModifier,
  });
}

/// Takes an array of columns and an object of string values then converts each string value
/// to its mapped type.
///
/// `columns` All of the columns
/// `record` The map of string values
/// `skipTypes` The array of types that should not be converted
///
/// ```dart
/// convertChangeData([{name: 'first_name', type: 'text'}, {name: 'age', type: 'int4'}], {'first_name': 'Paul', 'age':'33'}, {})
/// => { 'first_name': 'Paul', 'age': 33 }
/// ```
Map<String, dynamic> convertChangeData(
  List<Map<String, dynamic>> columns,
  Map<String, dynamic> record, {
  List<String>? skipTypes,
}) {
  final result = <String, dynamic>{};
  final _skipTypes = skipTypes ?? [];
  final parsedColumns = <PostgresColumn>[];

  for (final element in columns) {
    final name = element['name'] as String?;
    final type = element['type'] as String?;
    if (name != null && type != null) {
      parsedColumns.add(PostgresColumn(name, type));
    }
  }

  record.forEach((key, value) {
    result[key] = convertColumn(key, parsedColumns, record, _skipTypes);
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
dynamic convertColumn(
  String columnName,
  List<PostgresColumn> columns,
  Map<String, dynamic> record,
  List<String> skipTypes,
) {
  final column = columns.firstWhereOrNull((x) => x.name == columnName);
  final columnValue = record[columnName];
  final columnValueStr = columnValue == null
      ? null
      : columnValue is String
          ? columnValue
          : columnValue.toString();

  if (column != null && !skipTypes.contains(column.type)) {
    return convertCell(column.type, columnValueStr);
  }
  return noop(columnValueStr);
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
dynamic convertCell(String type, dynamic value) {
  // if data type is an array
  if (type[0] == '_') {
    final dataType = type.substring(1);
    return toArray(value, dataType);
  }

  final typeEnum = PostgresTypes.values
      .firstWhereOrNull((e) => e.toString() == 'PostgresTypes.$type');
  // If not null, convert to correct type.
  switch (typeEnum) {
    case PostgresTypes.bool:
      return toBoolean(value);
    case PostgresTypes.float4:
    case PostgresTypes.float8:
    case PostgresTypes.numeric:
      return toDouble(value);
    case PostgresTypes.int2:
    case PostgresTypes.int4:
    case PostgresTypes.int8:
    case PostgresTypes.oid:
      return toInt(value);
    case PostgresTypes.json:
    case PostgresTypes.jsonb:
      return toJson(value);
    case PostgresTypes.timestamp:
      return toTimestampString(value); // Format to be consistent with PostgREST
    case PostgresTypes.abstime: // To allow users to cast it based on Timezone
    case PostgresTypes.date: // To allow users to cast it based on Timezone
    case PostgresTypes.daterange:
    case PostgresTypes.int4range:
    case PostgresTypes.int8range:
    case PostgresTypes.money:
    case PostgresTypes.reltime: // To allow users to cast it based on Timezone
    case PostgresTypes.time: // To allow users to cast it based on Timezone
    case PostgresTypes
        .timestamptz: // To allow users to cast it based on Timezone
    case PostgresTypes.timetz: // To allow users to cast it based on Timezone
    case PostgresTypes.tsrange:
    case PostgresTypes.tstzrange:
      return noop(value);
    default:
      // Return the value for remaining types
      return noop(value);
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
List<dynamic> toArray(dynamic recordValue, String type) {
  // this takes off the '{' & '}'
  final stringEnriched = recordValue.substring(1, recordValue.length - 1);

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
