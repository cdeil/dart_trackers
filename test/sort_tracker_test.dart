import 'package:test/test.dart';

import 'conformance_harness.dart';

void main() {
  group('SORTTracker conformance', () {
    runTrackerConformance('sort_cases.json', sortFromParams);
  });
}
