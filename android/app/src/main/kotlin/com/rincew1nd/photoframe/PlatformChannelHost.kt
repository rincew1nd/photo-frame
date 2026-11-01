package com.rincew1nd.photoframe

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PlatformChannelHost(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private val audioManager =
        activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false

    private val audioFocusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            val event = when (change) {
                AudioManager.AUDIOFOCUS_LOSS -> "lost"
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "transient"
                AudioManager.AUDIOFOCUS_GAIN -> "gain"
                else -> null
            }
            when (change) {
                AudioManager.AUDIOFOCUS_LOSS -> hasAudioFocus = false
                AudioManager.AUDIOFOCUS_GAIN -> hasAudioFocus = true
            }
            if (event != null) {
                activity.runOnUiThread {
                    channel?.invokeMethod("audioFocusChanged", event)
                }
            }
        }

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
    }

    private fun requestAudioFocus(): Boolean {
        if (hasAudioFocus) {
            return true
        }
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build()
            audioFocusRequest = request
            audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        hasAudioFocus = granted
        return granted
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusListener)
        }
        hasAudioFocus = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestAudioFocus" -> result.success(requestAudioFocus())
            "abandonAudioFocus" -> {
                abandonAudioFocus()
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
            "getAutostartSupported" -> result.success(true)
            "setStartOnBoot" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                activity.getSharedPreferences("photo_frame", Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean("start_on_boot", enabled)
                    .apply()
                result.success(null)
            }
            "isIgnoringBatteryOptimizations" -> {
                val powerManager =
                    activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(
                    powerManager.isIgnoringBatteryOptimizations(activity.packageName)
                )
            }
            "requestIgnoreBatteryOptimizations" -> {
                val started = try {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:${activity.packageName}"),
                        )
                    )
                    true
                } catch (_: Exception) {
                    try {
                        activity.startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        )
                        true
                    } catch (_: Exception) {
                        false
                    }
                }
                result.success(started)
            }
            "openAutostartSettings" -> {
                val started = try {
                    val intent = Intent("miui.intent.action.OP_AUTO_START").apply {
                        addCategory(Intent.CATEGORY_DEFAULT)
                        putExtra("extra_pkgname", activity.packageName)
                    }
                    activity.startActivity(intent)
                    true
                } catch (_: Exception) {
                    try {
                        activity.startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:${activity.packageName}"),
                            )
                        )
                        true
                    } catch (_: Exception) {
                        false
                    }
                }
                result.success(started)
            }
            "openHomeSettings" -> {
                val started = try {
                    activity.startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
                    true
                } catch (_: Exception) {
                    false
                }
                result.success(started)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "com.rincew1nd.photoframe/platform"
    }
}
