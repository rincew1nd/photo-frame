package com.rincew1nd.photoframe

import android.app.Activity
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PlatformChannelHost(private val activity: Activity) : MethodChannel.MethodCallHandler {
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success(Build.VERSION.SDK_INT)
            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                if (enabled) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            "setBrightness" -> {
                val value = call.argument<Double>("brightness")
                val attributes = activity.window.attributes
                attributes.screenBrightness = when {
                    value == null -> WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    value < 0.0 -> 0.0f
                    value > 1.0 -> 1.0f
                    else -> value.toFloat()
                }
                activity.window.attributes = attributes
                result.success(null)
            }
            "getAutostartSupported" -> result.success(false)
            "supportsHevc1440p" -> result.success(supportsHevc1440p())
            else -> result.notImplemented()
        }
    }

    private fun supportsHevc1440p(): Boolean {
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        for (info in list.codecInfos) {
            if (info.isEncoder) continue
            for (type in info.supportedTypes) {
                if (!type.equals("video/hevc", true)) continue
                try {
                    val caps = info.getCapabilitiesForType(type).videoCapabilities ?: continue
                    if (caps.isSizeSupported(1920, 1440) || caps.isSizeSupported(1440, 1920)) {
                        return true
                    }
                } catch (_: Exception) {
                }
            }
        }
        return false
    }

    companion object {
        private const val CHANNEL = "com.rincew1nd.photoframe/platform"
    }
}
