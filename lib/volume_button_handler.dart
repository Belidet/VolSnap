import 'dart:async';
import 'package:flutter/services.dart';

/// Handles volume button events from native platforms.
class VolumeButtonHandler {
  static const MethodChannel _channel =
      MethodChannel('com.example.volume_camera/volume');

  static final StreamController<VolumeButtonEvent> _controller =
      StreamController<VolumeButtonEvent>.broadcast();

  static Stream<VolumeButtonEvent> get stream => _controller.stream;

  static bool _initialized = false;

  /// Must be called once at startup.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeUp') {
        _controller.add(VolumeButtonEvent.up);
      } else if (call.method == 'volumeDown') {
        _controller.add(VolumeButtonEvent.down);
      }
    });

    try {
      await _channel.invokeMethod('startListening');
    } on PlatformException catch (e) {
      print('Failed to start volume listener: $e');
    }
  }

  static Future<void> dispose() async {
    try {
      await _channel.invokeMethod('stopListening');
    } catch (_) {}
  }
}

enum VolumeButtonEvent { up, down }
