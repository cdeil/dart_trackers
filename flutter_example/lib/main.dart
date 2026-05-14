import 'dart:math' as math;

import 'package:dart_trackers/dart_trackers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'tracking_overlay.dart';
import 'yolo_camera_stub.dart' if (dart.library.io) 'yolo_camera_mobile.dart';

void main() {
  runApp(const TrackersFlutterExampleApp());
}

class TrackersFlutterExampleApp extends StatelessWidget {
  final Widget? demoVideoPage;
  final Widget? yoloCameraPage;

  const TrackersFlutterExampleApp({
    super.key,
    this.demoVideoPage,
    this.yoloCameraPage,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dart_trackers Flutter example',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: ExampleHomePage(
        demoVideoPage: demoVideoPage,
        yoloCameraPage: yoloCameraPage,
      ),
    );
  }
}

class ExampleHomePage extends StatelessWidget {
  final Widget? demoVideoPage;
  final Widget? yoloCameraPage;

  const ExampleHomePage({super.key, this.demoVideoPage, this.yoloCameraPage});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('dart_trackers Flutter example'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.video_library), text: 'Demo videos'),
              Tab(icon: Icon(Icons.camera_alt), text: 'YOLO camera'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            demoVideoPage ?? const DemoVideoTrackingPage(),
            yoloCameraPage ?? buildYoloCameraPage(),
          ],
        ),
      ),
    );
  }
}

class DemoClip {
  final String title;
  final Uri uri;
  final String detectorNote;

  const DemoClip({
    required this.title,
    required this.uri,
    required this.detectorNote,
  });
}

final _clips = [
  DemoClip(
    title: 'Bikes',
    uri: Uri.parse(
      'https://storage.googleapis.com/com-roboflow-marketing/supervision/video-examples/bikes-1280x720-1.mp4',
    ),
    detectorNote: 'Python trackers demo uses RF-DETR small on this clip.',
  ),
  DemoClip(
    title: 'Vehicles',
    uri: Uri.parse(
      'https://storage.googleapis.com/com-roboflow-marketing/supervision/video-examples/vehicles-1280x720.mp4',
    ),
    detectorNote: 'Useful car/truck demo for tracker ID continuity.',
  ),
  DemoClip(
    title: 'Suitcases / people',
    uri: Uri.parse(
      'https://storage.googleapis.com/com-roboflow-marketing/supervision/video-examples/suitcases-1280x720-4.mp4',
    ),
    detectorNote: 'People/object demo from the Python Gradio app.',
  ),
];

class DemoVideoTrackingPage extends StatefulWidget {
  const DemoVideoTrackingPage({super.key});

  @override
  State<DemoVideoTrackingPage> createState() => _DemoVideoTrackingPageState();
}

class _DemoVideoTrackingPageState extends State<DemoVideoTrackingPage> {
  final Tracker _tracker = ByteTrackTracker(minimumConsecutiveFrames: 1);
  late VideoPlayerController _controller;
  int _clipIndex = 0;
  List<TrackedDetection> _tracked = const [];

  DemoClip get _clip => _clips[_clipIndex];

  @override
  void initState() {
    super.initState();
    _loadClip();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadClip() async {
    _tracker.reset();
    _tracked = const [];
    _controller = VideoPlayerController.networkUrl(_clip.uri)
      ..addListener(_onVideoTick);
    await _controller.initialize();
    await _controller.setLooping(true);
    await _controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _selectClip(int index) async {
    if (index == _clipIndex) return;
    final old = _controller;
    old.removeListener(_onVideoTick);
    _clipIndex = index;
    await old.dispose();
    await _loadClip();
  }

  void _onVideoTick() {
    if (!_controller.value.isInitialized) return;
    final seconds = _controller.value.position.inMilliseconds / 1000.0;
    final detections = _syntheticDetections(seconds, _clipIndex);
    final tracked = _tracker.update(detections);
    _tracked = [
      for (var i = 0; i < tracked.length; i++)
        TrackedDetection(
          box: Rect.fromLTRB(
            tracked.xyxy[i * 4],
            tracked.xyxy[i * 4 + 1],
            tracked.xyxy[i * 4 + 2],
            tracked.xyxy[i * 4 + 3],
          ),
          trackerId: tracked.trackerId?[i] ?? -1,
          confidence: tracked.confidenceAt(i),
          label: _labelForClass(tracked.classId?[i] ?? 0),
        ),
    ];
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final initialized = _controller.value.isInitialized;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'This tab mirrors the Python trackers video-demo architecture: video '
          'playback and detections are separate from tracking. The checked-in '
          'example uses deterministic sample detections so it runs on Android, '
          'iOS, and web without bundling AGPL detector code into dart_trackers.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _clips.length; i++)
              ChoiceChip(
                label: Text(_clips[i].title),
                selected: i == _clipIndex,
                onSelected: (_) => _selectClip(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: initialized ? _controller.value.aspectRatio : 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: initialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(_controller),
                        CustomPaint(painter: TrackingOverlayPainter(_tracked)),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(_clip.detectorNote),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: initialized
              ? () {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                }
              : null,
          icon: Icon(
            initialized && _controller.value.isPlaying
                ? Icons.pause
                : Icons.play_arrow,
          ),
          label: Text(
            initialized && _controller.value.isPlaying ? 'Pause' : 'Play',
          ),
        ),
      ],
    );
  }
}

Detections _syntheticDetections(double seconds, int clipIndex) {
  final boxes = <List<num>>[];
  final confidence = <num>[];
  final classId = <int>[];
  final n = switch (clipIndex) {
    0 => 5,
    1 => 6,
    _ => 4,
  };
  for (var i = 0; i < n; i++) {
    final phase = seconds * (0.05 + i * 0.006) + i * 0.13;
    final w = 0.08 + (i % 3) * 0.015;
    final h = 0.16 + (i % 2) * 0.04;
    final cx = (0.12 + phase) % 0.82 + w / 2;
    final cy = 0.28 + (i % 3) * 0.18 + math.sin(seconds + i) * 0.015;
    boxes.add([
      (cx - w / 2).clamp(0.0, 0.98),
      (cy - h / 2).clamp(0.0, 0.98),
      (cx + w / 2).clamp(0.02, 1.0),
      (cy + h / 2).clamp(0.02, 1.0),
    ]);
    confidence.add(0.88 - (i % 4) * 0.08);
    classId.add(clipIndex == 1 ? 2 : 0);
  }
  return Detections.fromRows(boxes, confidence: confidence, classId: classId);
}

String _labelForClass(int classId) {
  return switch (classId) {
    0 => 'person',
    1 => 'bicycle',
    2 => 'car',
    _ => 'object',
  };
}
