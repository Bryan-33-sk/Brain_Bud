package com.example.brain_bud

import android.app.*
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.content.SharedPreferences
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class AppMonitorService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var isMonitoring = AtomicBoolean(false)
    private var lastDetectedPackage: String? = null
    private var lastDetectionTime: Long = 0

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayShownForPackage: String? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    
    // Default social media packages (used as fallback if no user selection)
    private val defaultSocialMediaPackages = setOf(
        "com.instagram.android",
        "com.facebook.katana",
        "com.facebook.orca",
        "com.whatsapp",
        "org.telegram.messenger",
        "com.snapchat.android",
        "com.zhiliaoapp.musically",
        "com.twitter.android",
        "com.linkedin.android",
        "com.reddit.frontpage",
        "com.discord",
        "com.pinterest",
        "com.google.android.youtube",
    )
    
    companion object {
        const val TAG = "AppMonitorService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "app_monitor_channel"
        private const val MONITOR_INTERVAL_MS = 500L // Check every 500ms
        
        // Static reference to MethodChannel (set from MainActivity)
        @Volatile
        var methodChannel: MethodChannel? = null
        
        fun startService(context: Context) {
            val intent = Intent(context, AppMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, AppMonitorService::class.java)
            context.stopService(intent)
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors app launches for interventions"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Brain Bud Monitoring")
                .setContentText("Monitoring app launches")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Brain Bud Monitoring")
                .setContentText("Monitoring app launches")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isMonitoring.get()) {
            startMonitoring()
        }
        return START_STICKY // Restart if killed
    }
    
    private fun startMonitoring() {
        if (isMonitoring.getAndSet(true)) {
            return
        }
        
        Log.d(TAG, "Starting app launch monitoring")
        
        val runnable = object : Runnable {
            override fun run() {
                if (isMonitoring.get()) {
                    checkForAppLaunches()
                    handler.postDelayed(this, MONITOR_INTERVAL_MS)
                }
            }
        }
        
        handler.post(runnable)
    }
    
    private fun stopMonitoring() {
        isMonitoring.set(false)
        Log.d(TAG, "Stopped app launch monitoring")
    }
    
    private fun checkForAppLaunches() {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val currentTime = System.currentTimeMillis()
            val startTime = currentTime - 1000 // Check last 1 second
            
            val usageEvents = usageStatsManager.queryEvents(startTime, currentTime)
            val event = UsageEvents.Event()
            
            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                    val packageName = event.packageName ?: continue
                    
                    // Check if it's a social media app
                    if (isSocialMediaApp(packageName)) {
                        Log.d(TAG, "Social media app detected: $packageName")
                        notifyAppLaunch(packageName)
                    }
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "No permission to query usage events", e)
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Error checking app launches", e)
        }
    }
    
    private fun isSocialMediaApp(packageName: String): Boolean {
        // First check user's custom selection (from Flutter's SharedPreferences)
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val monitoredAppsJson = prefs.getString("flutter.monitored_apps_json", null)
        
        if (monitoredAppsJson != null) {
            try {
                val jsonArray = org.json.JSONArray(monitoredAppsJson)
                for (i in 0 until jsonArray.length()) {
                    if (jsonArray.getString(i) == packageName) {
                        return true
                    }
                }
                // User has a custom selection but this app isn't in it
                return false
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse monitored apps JSON, using defaults", e)
            }
        }
        
        // Fallback to default list if no user selection
        // Check exact matches first
        if (defaultSocialMediaPackages.contains(packageName)) {
            return true
        }
        
        // Check by keywords
        val lowerPackage = packageName.toLowerCase()
        val socialMediaKeywords = listOf(
            "facebook", "instagram", "whatsapp", "telegram", "snapchat",
            "tiktok", "twitter", "linkedin", "messenger", "reddit",
            "discord", "pinterest", "youtube"
        )
        
        return socialMediaKeywords.any { lowerPackage.contains(it) }
    }
    
    private fun notifyAppLaunch(packageName: String) {
        val currentTime = System.currentTimeMillis()
        
        // Prevent duplicate notifications for the same app within 2 seconds
        if (packageName == lastDetectedPackage && 
            (currentTime - lastDetectionTime) < 2000) {
            return
        }
        
        lastDetectedPackage = packageName
        lastDetectionTime = currentTime

        // Increment attempt counter in Flutter's SharedPreferences BEFORE showing overlay
        // This ensures the counter is always accurate, even if Flutter isn't running
        incrementLaunchAttempt(packageName)

        // Native overlay window (shows on top of other apps) - requires SYSTEM_ALERT_WINDOW permission
        try {
            showNativeOverlay(packageName)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to show native overlay (continuing without overlay): $packageName", e)
        }
        
        // Always store in SharedPreferences (fallback mechanism)
        // Store timestamp as String for Flutter compatibility
        val prefs = getSharedPreferences("brain_bud_prefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("last_detected_package", packageName)
            putString("last_detection_time", currentTime.toString())
            putBoolean("new_app_detected", true)
            apply()
        }
        
        // Try to push event directly to Flutter via MethodChannel (event push)
        // This is optional - if it fails, Flutter will read from SharedPreferences
        val channel = methodChannel
        if (channel != null) {
            try {
                handler.post {
                    try {
                        channel.invokeMethod("onAppLaunch", mapOf(
                            "packageName" to packageName,
                            "timestamp" to currentTime
                        ))
                        Log.d(TAG, "Pushed app launch event to Flutter: $packageName")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to invoke MethodChannel (Flutter will use SharedPreferences fallback): $packageName", e)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to post to handler (Flutter will use SharedPreferences fallback): $packageName", e)
            }
        } else {
            Log.d(TAG, "MethodChannel not available, Flutter will use SharedPreferences: $packageName")
        }
        
        Log.d(TAG, "Stored app launch detection: $packageName")
    }
    
    /// Increment launch attempt counter in Flutter's SharedPreferences
    private fun incrementLaunchAttempt(packageName: String) {
        try {
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
            val flutterKey = "flutter.launch_attempts_$today"
            
            // Read current attempts
            val attemptsJson = flutterPrefs.getString(flutterKey, "{}") ?: "{}"
            val jsonObject = org.json.JSONObject(attemptsJson)
            
            // Increment for this package
            val currentCount = jsonObject.optInt(packageName, 0)
            jsonObject.put(packageName, currentCount + 1)
            
            // Save back
            flutterPrefs.edit().putString(flutterKey, jsonObject.toString()).apply()
            
            Log.d(TAG, "Incremented attempt for $packageName: ${currentCount + 1}")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to increment launch attempt for $packageName", e)
        }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun showNativeOverlay(packageName: String) {
        if (!canDrawOverlays()) {
            Log.w(TAG, "Overlay permission not granted; cannot show native overlay for $packageName")
            return
        }

        // Avoid spamming overlay repeatedly for the same app while it stays in foreground
        if (overlayView != null && overlayShownForPackage == packageName) {
            return
        }

        handler.post {
            removeNativeOverlayInternal()
            requestAudioFocusForOverlay()

            val wm = windowManager ?: return@post

            val appLabel = getAppLabel(packageName)

            // Get attempt count from Flutter's SharedPreferences
            // Flutter stores in "FlutterSharedPreferences" with "flutter." prefix on keys
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
            val flutterKey = "flutter.launch_attempts_$today"
            val attemptsJson = flutterPrefs.getString(flutterKey, "{}") ?: "{}"
            
            var attemptCount = 0
            try {
                val jsonObject = org.json.JSONObject(attemptsJson)
                attemptCount = jsonObject.optInt(packageName, 0)
                Log.d(TAG, "Attempt count for $packageName: $attemptCount (from key: $flutterKey)")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse attempts JSON: $attemptsJson", e)
            }

            // Full-screen black container
            val container = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF000000.toInt()) // solid black
                gravity = Gravity.CENTER
                setPadding(48, 0, 48, 0)
            }

            // Top text with highlighted "think twice"
            val topText = TextView(this).apply {
                val fullText = "...your brain gets a\nchance to think twice:"
                val spannableText = android.text.SpannableString(fullText)
                val thinkStart = fullText.indexOf("think twice")
                val thinkEnd = thinkStart + "think twice".length
                
                spannableText.setSpan(
                    android.text.style.ForegroundColorSpan(0xFF7C3AED.toInt()),
                    thinkStart,
                    thinkEnd,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                spannableText.setSpan(
                    android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                    thinkStart,
                    thinkEnd,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                
                text = spannableText
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 100, 0, 0)
            }

            // Spacer
            val spacer1 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }

            // Large centered number
            val numberText = TextView(this).apply {
                text = attemptCount.toString()
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 72f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 8)
            }

            // Attempts text
            val attemptsText = TextView(this).apply {
                text = "attempts to open $appLabel within the\nlast 24 hours."
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 16f
                gravity = Gravity.CENTER
            }

            // Spacer
            val spacer2 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }

            // Purple button
            val dontOpenBtn = Button(this).apply {
                text = "I don't want to open $appLabel"
                setBackgroundColor(0xFF7C3AED.toInt())
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 16f
                setAllCaps(false)
                setOnClickListener {
                    try {
                        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(homeIntent)
                    } catch (_: Exception) {
                    }
                    removeNativeOverlay()
                }
            }

            // Continue link
            val continueLink = TextView(this).apply {
                text = "Continue on $appLabel"
                setTextColor(0xCCFFFFFF.toInt()) // white with opacity
                textSize = 14f
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 80)
                paintFlags = paintFlags or android.graphics.Paint.UNDERLINE_TEXT_FLAG
                setOnClickListener {
                    removeNativeOverlay()
                }
            }

            // Add views to container
            container.addView(topText)
            container.addView(spacer1)
            container.addView(numberText)
            container.addView(attemptsText)
            container.addView(spacer2)
            container.addView(
                dontOpenBtn,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
            )
            container.addView(continueLink)

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
            }

            try {
                wm.addView(container, params)
                overlayView = container
                overlayShownForPackage = packageName
                Log.d(TAG, "Native overlay shown for $packageName with $attemptCount attempts")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to add overlay view for $packageName", e)
                overlayView = null
                overlayShownForPackage = null
            }
        }
    }

    private fun removeNativeOverlay() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            removeNativeOverlayInternal()
        } else {
            handler.post { removeNativeOverlayInternal() }
        }
    }

    private fun removeNativeOverlayInternal() {
        val wm = windowManager ?: return
        val view = overlayView ?: return
        try {
            wm.removeView(view)
        } catch (_: Exception) {
        } finally {
            overlayView = null
            overlayShownForPackage = null
            abandonAudioFocusForOverlay()
        }
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { _ ->
        // No-op; holding focus to pause other apps while overlay is visible.
    }

    private fun requestAudioFocusForOverlay() {
        val am = audioManager ?: return
        if (hasAudioFocus) return

        hasAudioFocus = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()

                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener(audioFocusChangeListener)
                    .build()

                am.requestAudioFocus(audioFocusRequest!!) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    audioFocusChangeListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun abandonAudioFocusForOverlay() {
        val am = audioManager ?: return
        if (!hasAudioFocus) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(audioFocusChangeListener)
            }
        } catch (_: Exception) {
        } finally {
            hasAudioFocus = false
            audioFocusRequest = null
        }
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            packageName
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopMonitoring()
        removeNativeOverlay()
        Log.d(TAG, "Service destroyed")
    }
}

