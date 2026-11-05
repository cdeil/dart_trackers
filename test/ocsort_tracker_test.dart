import 'package:test/test.dart';

import 'conformance_harness.dart';

void main() {
  group('OCSORTTracker conformance', () {
    runTrackerConformance('ocsort_cases.json', ocsortFromParams);
  });
}
