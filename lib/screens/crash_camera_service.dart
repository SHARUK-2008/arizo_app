import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Manages front-camera video recording exclusively for crash/collision events.
/// Pre-buffers nothing — starts recording the moment a collision is detected,
/// and stops automatically after [recordDurationSeconds] seconds.
class CrashCameraService {
  static const int recordDurationSeconds = 15; // records 15s after crash
  static const int _preRollSeconds = 0;        // no pre-roll (front camera only on crash)

  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording   = false;
  Timer? _stopTimer;

  final _videoController = StreamController<String>.broadcast();

  /// Emits the file path of a completed crash video.
  Stream<String> get videoStream => _videoController.stream;

  bool get isRecording   => _isRecording;
  bool get isInitialized => _isInitialized;

  /// Call once at app start (or when NearMissScreen opens).
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      debugPrint('CrashCameraService: initialized (front camera)');
    } catch (e) {
      debugPrint('CrashCameraService: init failed — $e');
    }
  }

  /// Called by NearMissService when a collision is detected.
  /// Starts front-camera recording and auto-stops after [recordDurationSeconds].
  Future<String?> startCrashRecording() async {
    if (!_isInitialized || _isRecording) return null;
    if (_controller == null || !_controller!.value.isInitialized) return null;

    try {
      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/crash_${DateTime.now().millisecondsSinceEpoch}.mp4';

      await _controller!.startVideoRecording();
      _isRecording = true;
      debugPrint('CrashCameraService: recording started → $path');

      // Auto-stop after recordDurationSeconds
      _stopTimer = Timer(Duration(seconds: recordDurationSeconds), () async {
        await stopRecording();
      });

      return path;
    } catch (e) {
      debugPrint('CrashCameraService: startRecording failed — $e');
      return null;
    }
  }

  /// Stops recording and emits the video file path.
  Future<String?> stopRecording() async {
    if (!_isRecording || _controller == null) return null;
    _stopTimer?.cancel();

    try {
      final xfile = await _controller!.stopVideoRecording();
      _isRecording = false;
      debugPrint('CrashCameraService: saved → ${xfile.path}');
      _videoController.add(xfile.path);
      return xfile.path;
    } catch (e) {
      debugPrint('CrashCameraService: stopRecording failed — $e');
      _isRecording = false;
      return null;
    }
  }

  /// Returns a preview widget for the crash camera (small pip-style).
  CameraController? get cameraController => _controller;

  void dispose() {
    _stopTimer?.cancel();
    _controller?.dispose();
    _videoController.close();
  }
}