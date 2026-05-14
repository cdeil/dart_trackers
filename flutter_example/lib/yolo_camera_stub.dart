import 'package:flutter/material.dart';

Widget buildYoloCameraPage() {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Ultralytics YOLO camera inference is available in this example on '
        'Android and iOS. The video-demo tab runs on web using video playback '
        'plus detector outputs supplied separately.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
