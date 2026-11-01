package com.rincew1nd.photoframe

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MediaSessionHost(private val activity: Activity) :
    MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private val manager =
        activity.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private var controller: MediaController? = null
    private var listening = false
    private val component by lazy {
        ComponentName(activity, MediaSessionListenerService::class.java)
    }

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = emit()
        override fun onPlaybackStateChanged(state: PlaybackState?) = emit()
        override fun onSessionDestroyed() = refresh()
    }

    private val sessionsChanged =
        MediaSessionManager.OnActiveSessionsChangedListener { refresh() }

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
        refresh()
    }

    fun onResume() = refresh()

    fun dispose() {
        stopListening()
        controller?.unregisterCallback(callback)
        controller = null
    }

    private fun hasAccess(): Boolean {
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return flat.split(':').any { ComponentName.unflattenFromString(it) == component }
    }

    private fun startListening() {
        if (listening || !hasAccess()) {
            return
        }
        try {
            manager.addOnActiveSessionsChangedListener(sessionsChanged, component)
            listening = true
        } catch (_: SecurityException) {
        }
    }

    private fun stopListening() {
        if (!listening) {
            return
        }
        try {
            manager.removeOnActiveSessionsChangedListener(sessionsChanged)
        } catch (_: Exception) {
        }
        listening = false
    }

    private fun refresh() {
        if (!hasAccess()) {
            stopListening()
            bind(null)
            emit()
            return
        }
        startListening()
        val sessions = try {
            manager.getActiveSessions(component)
        } catch (_: SecurityException) {
            emptyList()
        }
        val chosen = sessions.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: sessions.firstOrNull { it.metadata != null }
        bind(chosen)
        emit()
    }

    private fun bind(next: MediaController?) {
        if (controller?.sessionToken == next?.sessionToken) {
            return
        }
        controller?.unregisterCallback(callback)
        controller = next
        next?.registerCallback(callback)
    }

    private fun emit() {
        channel?.invokeMethod("mediaState", stateMap())
    }

    private fun stateMap(): Map<String, Any?> {
        val current = controller
        val metadata = current?.metadata
        val playback = current?.playbackState
        val actions = playback?.actions ?: 0L
        return mapOf(
            "hasSession" to (metadata != null),
            "title" to metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
            "artist" to metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST),
            "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            "packageName" to current?.packageName,
            "playing" to (playback?.state == PlaybackState.STATE_PLAYING),
            "canPrevious" to ((actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS) != 0L),
            "canNext" to ((actions and PlaybackState.ACTION_SKIP_TO_NEXT) != 0L),
            "positionSeconds" to ((playback?.position ?: 0L).coerceAtLeast(0L) / 1000.0),
            "durationSeconds" to metadata
                ?.getLong(MediaMetadata.METADATA_KEY_DURATION)
                ?.takeIf { it > 0L }
                ?.div(1000.0),
        )
    }

    private fun control(action: String): Boolean {
        val current = controller ?: return false
        when (action) {
            "previous" -> current.transportControls.skipToPrevious()
            "next" -> current.transportControls.skipToNext()
            "toggle" -> {
                if (current.playbackState?.state == PlaybackState.STATE_PLAYING) {
                    current.transportControls.pause()
                } else {
                    current.transportControls.play()
                }
            }
            else -> return false
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getMediaState" -> {
                refresh()
                result.success(stateMap())
            }
            "mediaControl" -> result.success(control(call.argument<String>("action") ?: ""))
            "hasNotificationAccess" -> result.success(hasAccess())
            "openNotificationAccessSettings" -> {
                val started = try {
                    activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
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
        private const val CHANNEL = "com.rincew1nd.photoframe/media"
    }
}
