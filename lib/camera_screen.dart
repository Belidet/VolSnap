import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'volume_button_handler.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _currentIndex = 0;

  bool _isRecording = false;
  bool _isInitializing = true;
  bool _isSwitching = false;

  StreamSubscription<VolumeButtonEvent>? _volumeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      if (mounted) {
        setState(() => _isInitializing = false);
        _showMessage('Camera and microphone permissions are required.');
      }
      return;
    }

    // Initialize volume button handler
    await VolumeButtonHandler.initialize();
    _volumeSub = VolumeButtonHandler.stream.listen(_onVolumeEvent);

    // Load cameras
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      if (mounted) {
        setState(() => _isInitializing = false);
        _showMessage('No cameras found.');
      }
      return;
    }

    // Prefer back camera at start
    final backIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _currentIndex = backIndex >= 0 ? backIndex : 0;

    await _setupController(_cameras[_currentIndex]);

    if (mounted) setState(() => _isInitializing = false);
  }

  Future<void> _setupController(CameraDescription camera) async {
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await old?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() {});
    } catch (e) {
      _showMessage('Failed to init camera: $e');
    }
  }

  void _onVolumeEvent(VolumeButtonEvent event) {
    if (_isSwitching || _isRecording) return;
    switch (event) {
      case VolumeButtonEvent.up:
        _switchCamera();
        break;
      case VolumeButtonEvent.down:
        _captureAction();
        break;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isSwitching) return;
    _isSwitching = true;

    final newIndex = (_currentIndex + 1) % _cameras.length;
    _currentIndex = newIndex;

    try {
      await _setupController(_cameras[newIndex]);
    } finally {
      _isSwitching = false;
    }
  }

  Future<void> _captureAction() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _takePicture();
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final XFile file = await controller.takePicture();
      _showMessage('Photo saved: ${p.basename(file.path)}');
    } catch (e) {
      _showMessage('Failed to take picture: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.startVideoRecording();
      setState(() => _isRecording = true);
      _showMessage('Recording started');
    } catch (e) {
      _showMessage('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      final XFile file = await controller.stopVideoRecording();
      setState(() => _isRecording = false);
      _showMessage('Video saved: ${p.basename(file.path)}');
    } catch (e) {
      setState(() => _isRecording = false);
      _showMessage('Failed to stop recording: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _setupController(_cameras[_currentIndex]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _volumeSub?.cancel();
    VolumeButtonHandler.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : _controller == null || !_controller!.value.isInitialized
                ? const Center(
                    child: Text(
                      'Camera unavailable',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(child: _buildPreview()),
                      _buildTopBar(),
                      _buildBottomControls(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller!;
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(controller)),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _cameras[_currentIndex].lensDirection ==
                      CameraLensDirection.front
                  ? 'Front Camera'
                  : 'Back Camera',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const Spacer(),
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.fiber_manual_record,
                      color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text('REC', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Vol Up: Switch Camera  •  Vol Down: Photo  •  Tap Shutter: Video',
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Switch camera button
              IconButton(
                onPressed: _isRecording ? null : _switchCamera,
                icon: const Icon(Icons.cameraswitch, color: Colors.white),
                iconSize: 36,
              ),
              // Shutter button
              GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: _isRecording ? Colors.red : Colors.white24,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.videocam,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              // Photo button
              IconButton(
                onPressed: _isRecording ? null : _takePicture,
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                iconSize: 36,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
