package com.rincew1nd.photoframe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mediaSessionHost: MediaSessionHost? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformChannelHost(this).register(flutterEngine)
        mediaSessionHost = MediaSessionHost(this).also { it.register(flutterEngine) }
    }

    override fun onResume() {
        super.onResume()
        mediaSessionHost?.onResume()
    }

    override fun onDestroy() {
        mediaSessionHost?.dispose()
        mediaSessionHost = null
        super.onDestroy()
    }
}