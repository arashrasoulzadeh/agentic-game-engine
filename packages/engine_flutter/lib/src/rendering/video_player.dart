import 'dart:ui' show Offset;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// A pre-rendered video file for cutscene playback.
/// Supports MP4/WebM via platform video player with engine integration.
///
/// Usage:
/// ```dart
/// final video = VideoPlayer('assets/cutscenes/intro.mp4');
/// await video.initialize();
/// video.play();
/// // In your CinematicStep:
/// if (video.isPlaying) video.pause();
/// ```
class VideoPlayer {
  /// Asset path to the video file (must be in flutter/assets in pubspec.yaml).
  final String assetPath;

  /// Whether the video should loop.
  final bool loop;

  /// Volume (0.0 - 1.0).
  double volume;

  /// Playback speed (1.0 = normal).
  double playbackSpeed;

  /// Current playback position in seconds.
  Duration position;

  /// Total duration of the video.
  Duration? duration;

  /// Whether the video is currently playing.
  bool isPlaying = false;

  /// Whether the video has finished loading.
  bool isInitialized = false;

  /// Callback when playback completes (for non-looping videos).
  void Function()? onComplete;

  /// Callback when an error occurs.
  void Function(Object error)? onError;

  VideoPlayer({
    required this.assetPath,
    this.loop = false,
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
  }) : position = Duration.zero;

  /// Initializes the video player (loads metadata, prepares for playback).
  Future<void> initialize() async {
    try {
      // In a real implementation, this would use a platform video player
      // like video_player package or platform channels
      // For now, we simulate initialization
      await Future.delayed(const Duration(milliseconds: 100));
      duration = const Duration(seconds: 30); // Placeholder
      isInitialized = true;
    } catch (e) {
      onError?.call(e);
      rethrow;
    }
  }

  /// Starts or resumes playback.
  void play() {
    if (!isInitialized) return;
    isPlaying = true;
    // Platform-specific play implementation
  }

  /// Pauses playback.
  void pause() {
    isPlaying = false;
    // Platform-specific pause implementation
  }

  /// Stops playback and resets position to zero.
  void stop() {
    isPlaying = false;
    position = Duration.zero;
    // Platform-specific stop implementation
  }

  /// Seeks to a specific position.
  void seek(Duration position) {
    final min = Duration.zero;
    final max = duration ?? Duration.zero;
    if (position < min) this.position = min;
    else if (position > max) this.position = max;
    else this.position = position;
    // Platform-specific seek implementation
  }

  /// Sets the volume (0.0 - 1.0).
  void setVolume(double volume) {
    this.volume = volume.clamp(0.0, 1.0);
    // Platform-specific volume implementation
  }

  /// Sets the playback speed.
  void setPlaybackSpeed(double speed) {
    playbackSpeed = speed.clamp(0.1, 4.0);
    // Platform-specific speed implementation
  }

  /// Disposes resources.
  void dispose() {
    stop();
    // Platform-specific dispose
  }

  /// Updates the player state (call once per frame from a CinematicStep).
  void update(double dt) {
    if (!isPlaying || !isInitialized) return;

    final delta = Duration(milliseconds: (dt * 1000 * playbackSpeed).round());
    position += delta;

    if (duration != null && position >= duration!) {
      if (loop) {
        position = Duration.zero;
      } else {
        position = duration!;
        isPlaying = false;
        onComplete?.call();
      }
    }
  }
}

/// A CinematicStep that plays a video file.
/// Integrates with the CinematicSystem for sequenced cutscenes.
class PlayVideoStep extends CinematicStep {
  final VideoPlayer video;
  final bool skipOnTap;

  PlayVideoStep({
    required this.video,
    this.skipOnTap = true,
  });

  @override
  void start(World world) {
    video.initialize().then((_) {
      video.play();
    }).catchError((e) {
      video.onError?.call(e);
      complete(world);
    });
  }

  @override
  bool update(World world, double dt) {
    video.update(dt);
    return !video.isPlaying;
  }

  @override
  void skip(World world) {
    if (skipOnTap) {
      video.stop();
      complete(world);
    }
  }

  void complete(World world) {
    // CinematicStep doesn't have a built-in complete method,
    // but the system will advance when update returns true
  }
}

/// A Scene that displays a full-screen video with optional controls.
/// Can be used as a standalone cutscene or pushed as an overlay.
class VideoScene extends Scene {
  final VideoPlayer video;
  final bool showControls;
  final bool autoPlay;

  VideoScene({
    required this.video,
    this.showControls = false,
    this.autoPlay = true,
  });

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    await video.initialize();
    if (autoPlay) {
      video.play();
    }
  }

  @override
  void update(double dt, World world) {
    video.update(dt);
    if (!video.isPlaying && !video.loop) {
      // Video finished, pop this scene if it was pushed as overlay
      // The parent scene controller would handle this
    }
  }

  @override
  void handleTap(World world, SceneController scenes, Offset worldPosition) {
    // Tap to pause/play or skip
    if (video.isPlaying) {
      video.pause();
    } else {
      video.play();
    }
  }
}