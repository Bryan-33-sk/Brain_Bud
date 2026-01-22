package com.example.brain_bud

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/**
 * Accessibility Service for instant app detection.
 * This replaces the polling-based AppMonitorService for much faster detection.
 */
class AppAccessibilityService : AccessibilityService() {

    companion object {
        const val TAG = "AppAccessibilityService"
        
        @Volatile
        var instance: AppAccessibilityService? = null
            private set
        
        @Volatile
        var methodChannel: MethodChannel? = null
        
        fun isServiceRunning(): Boolean = instance != null
    }
    
    private val handler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayShownForPackage: String? = null
    
    private var lastDetectedPackage: String? = null
    private var lastDetectionTime: Long = 0
    
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    
    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { _ ->
        // No-op; just holding focus to pause other apps
    }
    
    // Default social media packages (used as fallback if no user selection)
    private val defaultSocialMediaPackages = setOf(
        "com.instagram.android",
        "com.facebook.katana",
        "com.facebook.orca",
        "com.whatsapp",
        "org.telegram.messenger",
        "com.snapchat.android",
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill", // TikTok alternate
        "com.twitter.android",
        "com.linkedin.android",
        "com.reddit.frontpage",
        "com.discord",
        "com.pinterest",
        "com.google.android.youtube",
    )
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        Log.d(TAG, "Accessibility Service created")
    }
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        
        // Configure the service
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            notificationTimeout = 100
        }
        serviceInfo = info
        
        Log.d(TAG, "Accessibility Service connected and configured")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                val packageName = event.packageName?.toString() ?: return
                
                // Skip our own app and system UI
                if (packageName == "com.example.brain_bud" ||
                    packageName == "com.android.systemui" ||
                    packageName.startsWith("com.android.launcher")) {
                    return
                }
                
                // Check if interventions are enabled
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val interventionsEnabled = prefs.getBoolean("flutter.interventions_enabled", true)
                
                if (!interventionsEnabled) {
                    return
                }
                
                // Check if it's a social media app
                if (isSocialMediaApp(packageName)) {
                    Log.d(TAG, "Social media app detected (instant): $packageName")
                    handleAppLaunch(packageName)
                }
            }
        }
    }
    
    override fun onInterrupt() {
        Log.d(TAG, "Accessibility Service interrupted")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
        removeNativeOverlayInternal()
        abandonAudioFocusForOverlay()
        Log.d(TAG, "Accessibility Service destroyed")
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
        val lowerPackage = packageName.lowercase()
        val socialMediaKeywords = listOf(
            "facebook", "instagram", "whatsapp", "telegram", "snapchat",
            "tiktok", "twitter", "linkedin", "messenger", "reddit",
            "discord", "pinterest", "youtube"
        )
        
        return socialMediaKeywords.any { lowerPackage.contains(it) }
    }
    
    private fun handleAppLaunch(packageName: String) {
        val currentTime = System.currentTimeMillis()
        
        // Prevent duplicate detections within 2 seconds
        if (packageName == lastDetectedPackage && 
            (currentTime - lastDetectionTime) < 2000) {
            return
        }
        
        lastDetectedPackage = packageName
        lastDetectionTime = currentTime
        
        // Increment attempt counter
        incrementLaunchAttempt(packageName)
        
        // Show overlay
        if (canDrawOverlays()) {
            showNativeOverlay(packageName)
        }
        
        // Notify Flutter (if channel is available)
        notifyFlutter(packageName, currentTime)
    }
    
    private fun incrementLaunchAttempt(packageName: String) {
        try {
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
            val flutterKey = "flutter.launch_attempts_$today"
            
            val attemptsJson = flutterPrefs.getString(flutterKey, "{}") ?: "{}"
            val jsonObject = org.json.JSONObject(attemptsJson)
            
            val currentCount = jsonObject.optInt(packageName, 0)
            jsonObject.put(packageName, currentCount + 1)
            
            flutterPrefs.edit().putString(flutterKey, jsonObject.toString()).apply()
            
            Log.d(TAG, "Incremented attempt for $packageName: ${currentCount + 1}")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to increment launch attempt for $packageName", e)
        }
    }
    
    private fun notifyFlutter(packageName: String, timestamp: Long) {
        val channel = methodChannel ?: return
        
        handler.post {
            try {
                channel.invokeMethod("onAppLaunch", mapOf(
                    "packageName" to packageName,
                    "timestamp" to timestamp
                ))
                Log.d(TAG, "Notified Flutter of app launch: $packageName")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to notify Flutter: $packageName", e)
            }
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
        // Avoid duplicate overlay
        if (overlayView != null && overlayShownForPackage == packageName) {
            return
        }
        
        handler.post {
            removeNativeOverlayInternal()
            requestAudioFocusForOverlay()
            
            val wm = windowManager ?: return@post
            val appLabel = getAppLabel(packageName)
            
            // Get attempt count
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
            val flutterKey = "flutter.launch_attempts_$today"
            val attemptsJson = flutterPrefs.getString(flutterKey, "{}") ?: "{}"
            
            var attemptCount = 0
            try {
                val jsonObject = org.json.JSONObject(attemptsJson)
                attemptCount = jsonObject.optInt(packageName, 0)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse attempts JSON", e)
            }
            
            // Build the overlay UI (same as AppMonitorService)
            val container = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF000000.toInt())
                gravity = Gravity.CENTER
                setPadding(48, 0, 48, 0)
            }
            
            // Top text
            val topText = TextView(this).apply {
                val fullText = "...your brain gets a\nchance to think twice:"
                val spannableText = android.text.SpannableString(fullText)
                val thinkStart = fullText.indexOf("think twice")
                val thinkEnd = thinkStart + "think twice".length
                
                spannableText.setSpan(
                    android.text.style.ForegroundColorSpan(0xFF7C3AED.toInt()),
                    thinkStart, thinkEnd,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                spannableText.setSpan(
                    android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                    thinkStart, thinkEnd,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                
                text = spannableText
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 100, 0, 0)
            }
            
            val spacer1 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
                )
            }
            
            val numberText = TextView(this).apply {
                text = attemptCount.toString()
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 72f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 8)
            }
            
            val attemptsText = TextView(this).apply {
                text = "attempts to open $appLabel within the\nlast 24 hours."
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 16f
                gravity = Gravity.CENTER
            }
            
            val spacer2 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
                )
            }
            
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
                    } catch (_: Exception) {}
                    removeNativeOverlay()
                }
            }
            
            val continueLink = TextView(this).apply {
                text = "Continue on $appLabel"
                setTextColor(0xCCFFFFFF.toInt())
                textSize = 14f
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 80)
                paintFlags = paintFlags or android.graphics.Paint.UNDERLINE_TEXT_FLAG
                setOnClickListener {
                    removeNativeOverlay()
                }
            }
            
            container.addView(topText)
            container.addView(spacer1)
            container.addView(numberText)
            container.addView(attemptsText)
            container.addView(spacer2)
            container.addView(dontOpenBtn, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ))
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
                Log.d(TAG, "Overlay shown for $packageName with $attemptCount attempts")
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
            packageName.split(".").lastOrNull() ?: packageName
        }
    }
}

