import 'package:test/test.dart';

import 'conformance_harness.dart';

void main() {
  group('CBIoUTracker conformance', () {
    runTrackerConformance('cbiou_cases.json', cbiouFromParams);
  });
}
