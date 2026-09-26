package com.example.volume_camera

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.volume_camera/volume"
    private lateinit var audioManager: AudioManager
    private lateinit var channel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private var lastVolume = 0
    private var listening = false

    private val volumeRunnable = object : Runnable {
        override fun run() {
            if (!listening) return
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            if (current > lastVolume) {
                channel.invokeMethod("volumeUp", null)
            } else if (current < lastVolume) {
                channel.invokeMethod("volumeDown", null)
            }
            lastVolume = current
            handler.postDelayed(this, 100)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    startListening()
                    result.success(null)
                }
                "stopListening" -> {
                    stopListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startListening() {
        if (listening) return
        listening = true
        lastVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        handler.postDelayed(volumeRunnable, 100)
    }

    private fun stopListening() {
        listening = false
        handler.removeCallbacks(volumeRunnable)
    }

    override fun onDestroy() {
        stopListening()
        super.onDestroy()
    }
}
