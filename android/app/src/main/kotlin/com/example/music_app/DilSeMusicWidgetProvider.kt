package com.example.music_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.max

class DilSeMusicWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PLAY_PAUSE -> {
                // Optimistic zero-latency UI toggle
                optimisticTogglePlayPause(context)
                sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            }
            ACTION_NEXT -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            ACTION_PREVIOUS -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            ACTION_SHUFFLE -> {
                optimisticToggleShuffle(context)
                dispatchCustomAction(context, "toggleShuffle")
            }
            ACTION_REPEAT -> {
                optimisticToggleRepeat(context)
                dispatchCustomAction(context, "toggleRepeat")
            }
            ACTION_SEEK -> {
                val percent = intent.getFloatExtra(EXTRA_SEEK_PERCENT, -1f)
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val durationMs = prefs.getLong("flutter.widget_duration_ms", 0L)
                if (percent in 0f..1f && durationMs > 0) {
                    val targetMs = (durationMs * percent).toLong().coerceIn(0L, durationMs)
                    prefs.edit()
                        .putLong("flutter.widget_position_ms", targetMs)
                        .putString("flutter.widget_position_text", formatDuration(targetMs))
                        .apply()
                    updateAllWidgets(context)
                    val channel = MainActivity.activeWidgetChannel
                    if (channel != null) {
                        Handler(Looper.getMainLooper()).post {
                            channel.invokeMethod("seekTo", mapOf("positionMs" to targetMs))
                        }
                    }
                }
            }
            ACTION_REWIND_10 -> {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val currentPos = prefs.getLong("flutter.widget_position_ms", 0L)
                val targetMs = (currentPos - 10000L).coerceAtLeast(0L)
                prefs.edit()
                    .putLong("flutter.widget_position_ms", targetMs)
                    .putString("flutter.widget_position_text", formatDuration(targetMs))
                    .apply()
                updateAllWidgets(context)
                val channel = MainActivity.activeWidgetChannel
                if (channel != null) {
                    Handler(Looper.getMainLooper()).post {
                        channel.invokeMethod("seekTo", mapOf("positionMs" to targetMs))
                    }
                } else {
                    sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_REWIND)
                }
            }
            ACTION_FORWARD_10 -> {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val currentPos = prefs.getLong("flutter.widget_position_ms", 0L)
                val durationMs = prefs.getLong("flutter.widget_duration_ms", 0L)
                val targetMs = if (durationMs > 0) (currentPos + 10000L).coerceAtMost(durationMs) else currentPos + 10000L
                prefs.edit()
                    .putLong("flutter.widget_position_ms", targetMs)
                    .putString("flutter.widget_position_text", formatDuration(targetMs))
                    .apply()
                updateAllWidgets(context)
                val channel = MainActivity.activeWidgetChannel
                if (channel != null) {
                    Handler(Looper.getMainLooper()).post {
                        channel.invokeMethod("seekTo", mapOf("positionMs" to targetMs))
                    }
                } else {
                    sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
                }
            }
            ACTION_PLAY_PLAYLIST -> {
                val playlistIndex = intent.getIntExtra(EXTRA_PLAYLIST_INDEX, 0)
                val playlistId = intent.getStringExtra(EXTRA_PLAYLIST_ID) ?: ""
                val playlistQuery = intent.getStringExtra(EXTRA_PLAYLIST_QUERY) ?: ""
                launchAppWithPlaylist(context, playlistIndex, playlistId, playlistQuery)
            }
            ACTION_UPDATE_WIDGET -> {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val thisWidget = ComponentName(context, DilSeMusicWidgetProvider::class.java)
                val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
                if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                    onUpdate(context, appWidgetManager, appWidgetIds)
                }
            }
        }
    }

    private fun optimisticTogglePlayPause(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val current = prefs.getBoolean("flutter.widget_is_playing", false)
            prefs.edit().putBoolean("flutter.widget_is_playing", !current).apply()
            updateAllWidgets(context)
        } catch (_: Exception) {}
    }

    private fun optimisticToggleShuffle(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val current = prefs.getBoolean("flutter.widget_is_shuffle", false)
            prefs.edit().putBoolean("flutter.widget_is_shuffle", !current).apply()
            updateAllWidgets(context)
        } catch (_: Exception) {}
    }

    private fun optimisticToggleRepeat(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val current = prefs.getBoolean("flutter.widget_is_repeat", false)
            prefs.edit().putBoolean("flutter.widget_is_repeat", !current).apply()
            updateAllWidgets(context)
        } catch (_: Exception) {}
    }

    private fun dispatchCustomAction(context: Context, action: String) {
        val channel = MainActivity.activeWidgetChannel
        if (channel != null) {
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod(action, null)
            }
            return
        }
        // App is in background or not running: update SharedPreferences directly without launching MainActivity
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = if (action == "toggleShuffle") "flutter.widget_is_shuffle" else "flutter.widget_is_repeat"
        val current = prefs.getBoolean(key, false)
        prefs.edit().putBoolean(key, !current).apply()
        updateAllWidgets(context)
    }

    private fun launchAppWithPlaylist(context: Context, index: Int, id: String, query: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("widget_action", "playPlaylist")
            putExtra("playlist_index", index)
            putExtra("playlist_id", id)
            putExtra("playlist_query", query)
        }
        context.startActivity(intent)
    }

    private fun sendMediaKeyEvent(context: Context, keyCode: Int) {
        val mediaReceiver = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
        val downIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = mediaReceiver
            setPackage(context.packageName)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        context.sendBroadcast(downIntent)

        val upIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = mediaReceiver
            setPackage(context.packageName)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
        }
        context.sendBroadcast(upIntent)
    }

    companion object {
        const val ACTION_PLAY_PAUSE = "com.example.music_app.ACTION_PLAY_PAUSE"
        const val ACTION_NEXT = "com.example.music_app.ACTION_NEXT"
        const val ACTION_PREVIOUS = "com.example.music_app.ACTION_PREVIOUS"
        const val ACTION_SHUFFLE = "com.example.music_app.ACTION_SHUFFLE"
        const val ACTION_REPEAT = "com.example.music_app.ACTION_REPEAT"
        const val ACTION_PLAY_PLAYLIST = "com.example.music_app.ACTION_PLAY_PLAYLIST"
        const val ACTION_UPDATE_WIDGET = "com.example.music_app.ACTION_UPDATE_WIDGET"
        const val ACTION_SEEK = "com.example.music_app.ACTION_SEEK"
        const val ACTION_REWIND_10 = "com.example.music_app.ACTION_REWIND_10"
        const val ACTION_FORWARD_10 = "com.example.music_app.ACTION_FORWARD_10"

        const val EXTRA_SEEK_PERCENT = "extra_seek_percent"
        const val EXTRA_PLAYLIST_INDEX = "extra_playlist_index"
        const val EXTRA_PLAYLIST_ID = "extra_playlist_id"
        const val EXTRA_PLAYLIST_QUERY = "extra_playlist_query"

        fun formatDuration(ms: Long): String {
            if (ms <= 0) return "0:00"
            val totalSeconds = ms / 1000
            val minutes = totalSeconds / 60
            val seconds = totalSeconds % 60
            return String.format("%d:%02d", minutes, seconds)
        }

        fun toTitleCase(input: String): String {
            if (input.isBlank()) return input
            return input.split(" ")
                .filter { it.isNotEmpty() }
                .joinToString(" ") { word ->
                    word.lowercase().replaceFirstChar { char ->
                        if (char.isLowerCase()) char.titlecase() else char.toString()
                    }
                }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val title = prefs.getString("flutter.widget_title", "DilSe Music") ?: "DilSe Music"
            val artist = prefs.getString("flutter.widget_artist", "Tap to play") ?: "Tap to play"
            val isPlaying = prefs.getBoolean("flutter.widget_is_playing", false)
            val isShuffle = prefs.getBoolean("flutter.widget_is_shuffle", false)
            val isRepeat = prefs.getBoolean("flutter.widget_is_repeat", false)
            val artworkPath = prefs.getString("flutter.widget_artwork_path", null)
            val dominantColorInt = prefs.getLong("flutter.widget_dominant_color", 0L).toInt()
            val positionMs = prefs.getLong("flutter.widget_position_ms", 0L)
            val durationMs = prefs.getLong("flutter.widget_duration_ms", 0L)
            val positionText = prefs.getString("flutter.widget_position_text", "0:00") ?: "0:00"
            val durationText = prefs.getString("flutter.widget_duration_text", "0:00") ?: "0:00"
            val playlistsJson = prefs.getString("flutter.widget_top_playlists_json", null)

            val views = RemoteViews(context.packageName, R.layout.dilse_music_widget)

            // 1. Resolve Album Artwork (Local File or Cached Web Image)
            var albumBitmap: Bitmap? = null
            if (!artworkPath.isNullOrEmpty()) {
                val file = File(artworkPath)
                if (file.exists()) {
                    try {
                        albumBitmap = BitmapFactory.decodeFile(artworkPath)
                    } catch (_: Exception) {}
                } else if (artworkPath.startsWith("http://") || artworkPath.startsWith("https://")) {
                    val safeHash = artworkPath.hashCode().toString().replace("-", "n")
                    val cachedArt = File(context.cacheDir, "widget_art_$safeHash.png")
                    if (cachedArt.exists()) {
                        try {
                            albumBitmap = BitmapFactory.decodeFile(cachedArt.absolutePath)
                        } catch (_: Exception) {}
                    } else {
                        // Asynchronously download and cache to disk, then trigger widget update
                        Thread {
                            try {
                                val url = java.net.URL(artworkPath)
                                val conn = url.openConnection() as java.net.HttpURLConnection
                                conn.connectTimeout = 3000
                                conn.readTimeout = 3000
                                conn.doInput = true
                                conn.connect()
                                val stream = conn.inputStream
                                val downloadedBmp = BitmapFactory.decodeStream(stream)
                                if (downloadedBmp != null) {
                                    cachedArt.outputStream().use { out ->
                                        downloadedBmp.compress(Bitmap.CompressFormat.PNG, 90, out)
                                    }
                                    Handler(Looper.getMainLooper()).post {
                                        updateAllWidgets(context)
                                    }
                                }
                            } catch (_: Exception) {}
                        }.start()
                    }
                }
            }

            if (albumBitmap != null) {
                val roundedArt = createRoundedBitmap(albumBitmap, 30f)
                views.setImageViewBitmap(R.id.widget_album_art, roundedArt)
            } else {
                views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_stat_music)
            }

            // 2. Resolve Dominant Dynamic Accent Color
            val dominantColor = if (dominantColorInt != 0) {
                dominantColorInt
            } else if (albumBitmap != null) {
                extractDominantColorFromBitmap(albumBitmap)
            } else {
                Color.parseColor("#E03E52") // Rich vibrant crimson fallback
            }

            // 3. Synthesize Dynamic Frosted Glass Background Canvas
            val bgBitmap = createDynamicGlassBackground(context, dominantColor)
            if (bgBitmap != null) {
                views.setImageViewBitmap(R.id.widget_background_image, bgBitmap)
            }

            // 4. Track Metadata (Formatted with Title Case Capitalization)
            views.setTextViewText(R.id.widget_song_title, toTitleCase(title))
            views.setTextViewText(R.id.widget_song_artist, toTitleCase(artist))

            // 5. Glowing Circular Play / Pause Deck
            val playPauseBitmap = createGlowingPlayButton(context, isPlaying, dominantColor)
            views.setImageViewBitmap(R.id.widget_btn_play_pause, playPauseBitmap)

            // 6. Responsive Shuffle & Repeat Tint States
            val activeColor = Color.WHITE
            val inactiveColor = Color.argb(90, 255, 255, 255)
            views.setInt(R.id.widget_btn_shuffle, "setColorFilter", if (isShuffle) activeColor else inactiveColor)
            views.setInt(R.id.widget_btn_repeat, "setColorFilter", if (isRepeat) activeColor else inactiveColor)

            // 7. Progress Bar & Monospace Timestamps
            val progress = if (durationMs > 0) {
                ((positionMs.toDouble() / durationMs.toDouble()) * 1000).toInt().coerceIn(0, 1000)
            } else {
                0
            }
            views.setProgressBar(R.id.widget_progress_bar, 1000, progress, false)
            views.setTextViewText(R.id.widget_time_current, positionText)
            views.setTextViewText(R.id.widget_time_total, durationText)

            // 8. PendingIntents for Touch Controls & Interactive Scrubber
            val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            // Click body to open app
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, openAppIntent, flag))

            // Play / Pause
            val playPauseIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_PLAY_PAUSE
            }
            views.setOnClickPendingIntent(R.id.widget_btn_play_pause, PendingIntent.getBroadcast(context, 1, playPauseIntent, flag))

            // Next
            val nextIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_NEXT
            }
            views.setOnClickPendingIntent(R.id.widget_btn_next, PendingIntent.getBroadcast(context, 2, nextIntent, flag))

            // Previous
            val prevIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_PREVIOUS
            }
            views.setOnClickPendingIntent(R.id.widget_btn_prev, PendingIntent.getBroadcast(context, 3, prevIntent, flag))

            // Shuffle
            val shuffleIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_SHUFFLE
            }
            views.setOnClickPendingIntent(R.id.widget_btn_shuffle, PendingIntent.getBroadcast(context, 4, shuffleIntent, flag))

            // Repeat
            val repeatIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_REPEAT
            }
            views.setOnClickPendingIntent(R.id.widget_btn_repeat, PendingIntent.getBroadcast(context, 5, repeatIntent, flag))

            // Interactive Scrubber Tap-To-Seek Zones (10 segments across the scrubber)
            val seekZoneIds = intArrayOf(
                R.id.widget_seek_zone_0,
                R.id.widget_seek_zone_1,
                R.id.widget_seek_zone_2,
                R.id.widget_seek_zone_3,
                R.id.widget_seek_zone_4,
                R.id.widget_seek_zone_5,
                R.id.widget_seek_zone_6,
                R.id.widget_seek_zone_7,
                R.id.widget_seek_zone_8,
                R.id.widget_seek_zone_9
            )
            for (i in seekZoneIds.indices) {
                val seekPercent = (i * 0.1f) + 0.05f
                val seekIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                    action = ACTION_SEEK
                    putExtra(EXTRA_SEEK_PERCENT, seekPercent)
                }
                views.setOnClickPendingIntent(
                    seekZoneIds[i],
                    PendingIntent.getBroadcast(context, 50 + i, seekIntent, flag)
                )
            }

            // Quick Rewind / Forward on Timestamps (-10s / +10s)
            val rewindIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_REWIND_10
            }
            views.setOnClickPendingIntent(R.id.widget_time_current, PendingIntent.getBroadcast(context, 70, rewindIntent, flag))

            val forwardIntent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                action = ACTION_FORWARD_10
            }
            views.setOnClickPendingIntent(R.id.widget_time_total, PendingIntent.getBroadcast(context, 71, forwardIntent, flag))

            // 9. Bottom Shelf: 5 Prominent Top Playlists / Quick-Launch Badges
            setupTopPlaylists(context, views, playlistsJson, dominantColor, flag)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun setupTopPlaylists(
            context: Context,
            views: RemoteViews,
            playlistsJson: String?,
            dominantColor: Int,
            flag: Int
        ) {
            val defaultPlaylists = listOf(
                Pair("Daily Mix", "Daily Mix"),
                Pair("Favorites", "Favorites"),
                Pair("Most Played", "Most Played"),
                Pair("History Replay", "History"),
                Pair("Chill Vibes", "Chill Vibes")
            )

            var parsedList: List<Triple<String, String, String>>? = null
            if (!playlistsJson.isNullOrEmpty()) {
                try {
                    val array = JSONArray(playlistsJson)
                    val list = mutableListOf<Triple<String, String, String>>()
                    for (i in 0 until array.length().coerceAtMost(5)) {
                        val obj = array.getJSONObject(i)
                        val title = obj.optString("title", "Mix")
                        val id = obj.optString("id", "")
                        val query = obj.optString("query", title)
                        list.add(Triple(toTitleCase(title), id, query))
                    }
                    if (list.isNotEmpty()) parsedList = list
                } catch (_: Exception) {}
            }

            val slotIds = intArrayOf(
                R.id.widget_playlist_0,
                R.id.widget_playlist_1,
                R.id.widget_playlist_2,
                R.id.widget_playlist_3,
                R.id.widget_playlist_4
            )
            val titleIds = intArrayOf(
                R.id.widget_playlist_title_0,
                R.id.widget_playlist_title_1,
                R.id.widget_playlist_title_2,
                R.id.widget_playlist_title_3,
                R.id.widget_playlist_title_4
            )
            val artIds = intArrayOf(
                R.id.widget_playlist_art_0,
                R.id.widget_playlist_art_1,
                R.id.widget_playlist_art_2,
                R.id.widget_playlist_art_3,
                R.id.widget_playlist_art_4
            )

            val badgeGradients = arrayOf(
                intArrayOf(Color.parseColor("#FF5E3A"), Color.parseColor("#FF2A68")),
                intArrayOf(Color.parseColor("#00B4DB"), Color.parseColor("#0083B0")),
                intArrayOf(Color.parseColor("#F7971E"), Color.parseColor("#FF7000")),
                intArrayOf(Color.parseColor("#11998E"), Color.parseColor("#38EF7D")),
                intArrayOf(Color.parseColor("#8E2DE2"), Color.parseColor("#4A00E0"))
            )

            for (i in 0 until 5) {
                val title = parsedList?.getOrNull(i)?.first ?: defaultPlaylists[i].first
                val id = parsedList?.getOrNull(i)?.second ?: "playlist_$i"
                val query = parsedList?.getOrNull(i)?.third ?: defaultPlaylists[i].second

                views.setTextViewText(titleIds[i], toTitleCase(title))

                // Render micro squircle gradient badge with centered vector icon
                val badgeBitmap = createPlaylistBadge(badgeGradients[i % badgeGradients.size], i)
                views.setImageViewBitmap(artIds[i], badgeBitmap)

                // Intent for tapping playlist
                val intent = Intent(context, DilSeMusicWidgetProvider::class.java).apply {
                    action = ACTION_PLAY_PLAYLIST
                    putExtra(EXTRA_PLAYLIST_INDEX, i)
                    putExtra(EXTRA_PLAYLIST_ID, id)
                    putExtra(EXTRA_PLAYLIST_QUERY, query)
                }
                views.setOnClickPendingIntent(slotIds[i], PendingIntent.getBroadcast(context, 10 + i, intent, flag))
            }
        }

        private fun createPlaylistBadge(colors: IntArray, iconType: Int): Bitmap {
            val size = 76
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(0f, 0f, size.toFloat(), size.toFloat(), colors, null, Shader.TileMode.CLAMP)
            }
            val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
            canvas.drawRoundRect(rect, 20f, 20f, paint)

            // Subtle inner glow border
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 1.5f
                color = Color.argb(60, 255, 255, 255)
            }
            canvas.drawRoundRect(RectF(1f, 1f, size - 1f, size - 1f), 19f, 19f, strokePaint)

            // Draw crisp white icon centered inside the badge
            val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.FILL
            }
            val center = size / 2f
            when (iconType) {
                0 -> { // Daily Mix: Music soundwave bars
                    val r = 2f
                    canvas.drawRoundRect(RectF(center - 12f, center - 6f, center - 8f, center + 6f), r, r, iconPaint)
                    canvas.drawRoundRect(RectF(center - 5f, center - 12f, center - 1f, center + 12f), r, r, iconPaint)
                    canvas.drawRoundRect(RectF(center + 2f, center - 16f, center + 6f, center + 16f), r, r, iconPaint)
                    canvas.drawRoundRect(RectF(center + 9f, center - 8f, center + 13f, center + 8f), r, r, iconPaint)
                }
                1 -> { // Favorites: Heart
                    val path = Path()
                    val w = 11f
                    val h = 11f
                    path.moveTo(center, center + h * 0.7f)
                    path.cubicTo(center - w * 1.2f, center - h * 0.2f, center - w * 0.7f, center - h * 1.1f, center, center - h * 0.3f)
                    path.cubicTo(center + w * 0.7f, center - h * 1.1f, center + w * 1.2f, center - h * 0.2f, center, center + h * 0.7f)
                    path.close()
                    canvas.drawPath(path, iconPaint)
                }
                2 -> { // Most Played: Star
                    val path = Path()
                    val rOuter = 12f
                    val rInner = 5.5f
                    for (step in 0 until 10) {
                        val angle = (step * Math.PI / 5 - Math.PI / 2).toFloat()
                        val r = if (step % 2 == 0) rOuter else rInner
                        val x = center + (r * Math.cos(angle.toDouble())).toFloat()
                        val y = center + (r * Math.sin(angle.toDouble())).toFloat()
                        if (step == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    path.close()
                    canvas.drawPath(path, iconPaint)
                }
                3 -> { // History Replay: Clock / Circular rewind
                    val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = Color.WHITE
                        style = Paint.Style.STROKE
                        strokeWidth = 2.5f
                    }
                    canvas.drawCircle(center, center, 11f, strokeP)
                    canvas.drawLine(center, center, center, center - 6.5f, strokeP)
                    canvas.drawLine(center, center, center + 5f, center, strokeP)
                }
                else -> { // Disc / Music Note
                    val path = Path()
                    path.addCircle(center - 5f, center + 6f, 4f, Path.Direction.CW)
                    path.moveTo(center - 1f, center + 6f)
                    path.lineTo(center - 1f, center - 8f)
                    path.lineTo(center + 8f, center - 11f)
                    path.lineTo(center + 8f, center + 3f)
                    path.addCircle(center + 4f, center + 3f, 4f, Path.Direction.CW)
                    canvas.drawPath(path, iconPaint)
                }
            }

            return bitmap
        }

        private fun createRoundedBitmap(source: Bitmap, cornerRadiusDp: Float): Bitmap {
            val size = 220
            val scaled = Bitmap.createScaledBitmap(source, size, size, true)
            val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            }
            val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
            canvas.drawRoundRect(rect, cornerRadiusDp, cornerRadiusDp, paint)
            return output
        }

        private fun createGlowingPlayButton(context: Context, isPlaying: Boolean, dominantColor: Int): Bitmap {
            val size = 120
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val center = size / 2f

            // 1. Soft Ambient Halo Glow matching dominant color
            val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    center, center, center,
                    intArrayOf(
                        Color.argb(175, Color.red(dominantColor), Color.green(dominantColor), Color.blue(dominantColor)),
                        Color.argb(70, Color.red(dominantColor), Color.green(dominantColor), Color.blue(dominantColor)),
                        Color.TRANSPARENT
                    ),
                    floatArrayOf(0.0f, 0.65f, 1.0f),
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawCircle(center, center, center, glowPaint)

            // 2. Solid Inner Circle Deck with Subtle Radial Gradient
            val deckPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    center, center - 6f, center * 0.70f,
                    intArrayOf(
                        Color.WHITE,
                        Color.parseColor("#FFF4EE"),
                        Color.parseColor("#F0E6DD")
                    ),
                    null,
                    Shader.TileMode.CLAMP
                )
            }
            val deckRadius = center * 0.68f
            canvas.drawCircle(center, center, deckRadius, deckPaint)

            // 3. Crisp Play or Pause Glyph
            val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#121216")
                style = Paint.Style.FILL
            }

            if (isPlaying) {
                // Pause bars
                val barWidth = 8f
                val barHeight = 26f
                val spacing = 7f
                canvas.drawRoundRect(RectF(center - spacing - barWidth, center - barHeight / 2, center - spacing, center + barHeight / 2), 3f, 3f, glyphPaint)
                canvas.drawRoundRect(RectF(center + spacing, center - barHeight / 2, center + spacing + barWidth, center + barHeight / 2), 3f, 3f, glyphPaint)
            } else {
                // Play triangle
                val path = Path().apply {
                    val half = 15f
                    moveTo(center - 10f, center - half)
                    lineTo(center + 14f, center)
                    lineTo(center - 10f, center + half)
                    close()
                }
                canvas.drawPath(path, glyphPaint)
            }

            return bitmap
        }

        private fun createDynamicGlassBackground(context: Context, dominantColor: Int): Bitmap? {
            val width = 720
            val height = 360
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
            val cornerRadius = 52f

            // Ensure dominantColor has enough vibrancy and saturation for ambient beauty
            val hsv = FloatArray(3)
            Color.colorToHSV(dominantColor, hsv)
            val vibrantHsv = floatArrayOf(
                hsv[0],
                maxOf(0.65f, hsv[1]),
                hsv[2].coerceIn(0.40f, 0.85f)
            )
            val vibrantColor = Color.HSVToColor(vibrantHsv)

            // 1. Base Dark Charcoal Obsidian Glass
            val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#FF101016")
            }
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, basePaint)

            // 2. Rich Multi-Stop Linear Gradient from top-left to bottom-right
            val gradientPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    0f, 0f, width.toFloat(), height.toFloat(),
                    intArrayOf(
                        Color.argb(130, Color.red(vibrantColor), Color.green(vibrantColor), Color.blue(vibrantColor)),
                        Color.argb(65, Color.red(vibrantColor), Color.green(vibrantColor), Color.blue(vibrantColor)),
                        Color.argb(205, 16, 16, 24)
                    ),
                    floatArrayOf(0.0f, 0.45f, 1.0f),
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, gradientPaint)

            // 3. Ambient Radial Glow behind the Album Art (Left side bloom)
            val albumGlow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    width * 0.22f, height * 0.35f, width * 0.50f,
                    intArrayOf(
                        Color.argb(165, Color.red(vibrantColor), Color.green(vibrantColor), Color.blue(vibrantColor)),
                        Color.argb(70, Color.red(vibrantColor), Color.green(vibrantColor), Color.blue(vibrantColor)),
                        Color.TRANSPARENT
                    ),
                    floatArrayOf(0f, 0.55f, 1f),
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, albumGlow)

            // 4. Subtle Bottom Vignette for crisp playlist icon and text readability
            val bottomVignette = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    0f, height * 0.50f, 0f, height.toFloat(),
                    Color.TRANSPARENT,
                    Color.argb(180, 10, 10, 16),
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, bottomVignette)

            // 5. Sleek Translucent Glass Highlight Border Outline
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 2.5f
                shader = LinearGradient(
                    0f, 0f, width.toFloat(), height.toFloat(),
                    intArrayOf(
                        Color.argb(110, 255, 255, 255),
                        Color.argb(45, Color.red(vibrantColor), Color.green(vibrantColor), Color.blue(vibrantColor)),
                        Color.argb(30, 255, 255, 255)
                    ),
                    null,
                    Shader.TileMode.CLAMP
                )
            }
            val strokeRect = RectF(1.25f, 1.25f, width - 1.25f, height - 1.25f)
            canvas.drawRoundRect(strokeRect, cornerRadius, cornerRadius, strokePaint)

            return bitmap
        }

        private fun extractDominantColorFromBitmap(bmp: Bitmap): Int {
            return try {
                val width = bmp.width
                val height = bmp.height
                var redSum = 0L
                var greenSum = 0L
                var blueSum = 0L
                var count = 0L
                val stepX = maxOf(1, width / 20)
                val stepY = maxOf(1, height / 20)
                for (x in 0 until width step stepX) {
                    for (y in 0 until height step stepY) {
                        val p = bmp.getPixel(x, y)
                        redSum += Color.red(p)
                        greenSum += Color.green(p)
                        blueSum += Color.blue(p)
                        count++
                    }
                }
                if (count == 0L) Color.parseColor("#E03E52")
                else Color.rgb((redSum / count).toInt(), (greenSum / count).toInt(), (blueSum / count).toInt())
            } catch (_: Exception) {
                Color.parseColor("#E03E52")
            }
        }

        fun updateAllWidgets(context: Context) {
            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val thisWidget = ComponentName(context, DilSeMusicWidgetProvider::class.java)
                val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
                if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                    for (id in appWidgetIds) {
                        updateAppWidget(context, appWidgetManager, id)
                    }
                }
            } catch (_: Exception) {}
        }
    }
}
