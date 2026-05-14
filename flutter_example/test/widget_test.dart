import 'package:dart_trackers_flutter_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('example app shows demo tabs', (tester) async {
    await tester.pumpWidget(
      const TrackersFlutterExampleApp(
        demoVideoPage: Center(child: Text('video placeholder')),
        yoloCameraPage: Center(child: Text('camera placeholder')),
      ),
    );

    expect(find.text('Demo videos'), findsOneWidget);
    expect(find.text('YOLO camera'), findsOneWidget);
  });
}
