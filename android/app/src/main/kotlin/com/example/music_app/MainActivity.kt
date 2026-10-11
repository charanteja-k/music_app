package com.example.music_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var widgetChannel: MethodChannel? = null

    companion object {
        @Volatile
        var activeWidgetChannel: MethodChannel? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        unlockHighRefreshRate()
        createNotificationChannel()
        keepAudioServiceDrawables()
        handleWidgetIntent(intent)
    }

    override fun onDestroy() {
        if (activeWidgetChannel == widgetChannel) {
            activeWidgetChannel = null
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.getStringExtra("widget_action") ?: return
        when (action) {
            "toggleShuffle" -> widgetChannel?.invokeMethod("toggleShuffle", null)
            "toggleRepeat" -> widgetChannel?.invokeMethod("toggleRepeat", null)
            "playPlaylist" -> {
                val index = intent.getIntExtra("playlist_index", 0)
                val id = intent.getStringExtra("playlist_id") ?: ""
                val query = intent.getStringExtra("playlist_query") ?: ""
                widgetChannel?.invokeMethod("playPlaylist", mapOf(
                    "index" to index,
                    "id" to id,
                    "query" to query
                ))
            }
        }
    }

    private fun unlockHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }
                val modes = display?.supportedModes
                val maxMode = modes?.maxByOrNull { it.refreshRate }
                if (maxMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.music_app/widget")
        widgetChannel = channel
        activeWidgetChannel = channel
        channel.setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                DilSeMusicWidgetProvider.updateAllWidgets(this)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        // Deliver pending action if any was queued prior to engine setup
        handleWidgetIntent(intent)
    }

    private fun keepAudioServiceDrawables() {
        // Explicit compile-time references to prevent AAPT/R8 resource shrinking
        val drawables = intArrayOf(
            R.drawable.audio_service_play_arrow,
            R.drawable.audio_service_pause,
            R.drawable.audio_service_stop,
            R.drawable.audio_service_skip_next,
            R.drawable.audio_service_skip_previous,
            R.drawable.audio_service_fast_forward,
            R.drawable.audio_service_fast_rewind,
            R.drawable.ic_stat_music,
            R.drawable.ic_widget_shuffle,
            R.drawable.ic_widget_repeat
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "com.example.music_app.channel.audio_playback_v3"
            val channelName = "DilSe Music Playback"
            val channelDescription = "Music playback controls and lock screen notification"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
