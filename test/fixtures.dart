import 'fixtures.g.dart';

String fixtureJson(String name) {
  final json = fixtureJsonByName[name];
  if (json == null) {
    throw ArgumentError.value(name, 'name', 'Unknown fixture');
  }
  return json;
}
