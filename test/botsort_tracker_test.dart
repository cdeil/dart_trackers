import 'package:test/test.dart';

import 'conformance_harness.dart';

void main() {
  group('BoTSORTTracker (no CMC) conformance', () {
    runTrackerConformance('botsort_cases.json', botsortFromParams);
  });
}
