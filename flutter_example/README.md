# dart_trackers Flutter example

This folder is a **separate Flutter application** that demonstrates using the
Apache-2.0 `dart_trackers` package in a real UI. It is intentionally outside the
pub.dev package in `../dart_trackers`.

## Licensing boundary

The core `dart_trackers` package stays Apache-2.0 and has zero runtime
dependencies.

This example app depends on `ultralytics_yolo`, which is AGPL-3.0 unless you have
an Ultralytics enterprise license. Keep this app separate from the package that
is published to pub.dev.

## What the Python trackers docs use

The Python `trackers` examples use RF-DETR via `inference` / `inference-models`:

- CLI default: `rfdetr-nano`
- Homepage example: `rfdetr-medium`
- Gradio demo examples: `rfdetr-small`, `rfdetr-nano`, and RF-DETR segmentation
    variants

The tracker itself is detector-agnostic. This Flutter app uses Ultralytics YOLO
for the optional mobile camera tab because it is currently the practical
on-device Flutter detector plugin for Android and iOS.

## Demo modes

### Demo videos tab

Runs on Android, iOS, and web. It streams the same public Roboflow video-example
URLs referenced by the Python demo app and overlays tracker results.

The checked-in demo uses deterministic sample detections to keep the repository
small and legally clean. For production-quality comparison videos, generate
per-frame detections on the Python side, bundle the resulting JSON assets, and
feed them through `dart_trackers` in this tab.

The source videos are not committed because the Roboflow marketing video asset
license is not documented here and large video files should not be part of the
Dart package or this source tree.

### YOLO camera tab

Runs on Android and iOS. It uses `YOLOView` from `ultralytics_yolo`, converts
`YOLOResult` boxes into `dart_trackers.Detections`, tracks them with
`ByteTrackTracker`, and draws Dart tracker IDs over the camera view.

On web, this tab shows an explanatory fallback because `ultralytics_yolo` does
not currently support web.

## Run

```bash
cd flutter_example
flutter pub get
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

The iOS target requires local code-signing setup.

## Validate

```bash
cd flutter_example
flutter analyze
flutter test
flutter build web --debug
flutter build apk --debug
flutter build ios --debug --simulator --no-codesign
```

Android/iOS builds require the usual platform SDKs and signing configuration.
