package com.example.brain_bud

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

private const val TAG = "BrainBudUsage"

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.brainbud.usage_stats/channel"
    private val INTERVENTION_CHANNEL = "com.brainbud.intervention/channel"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Usage stats channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getUsageStats" -> {
                    try {
                        // Support time window mode: "rolling24h" or "today" (default)
                        val mode = call.argument<String>("mode") ?: "today"
                        val usageStats = getUsageStats(mode)
                        result.success(usageStats)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to get usage stats", e)
                        result.error("ERROR", "Failed to get usage stats: ${e.message}", null)
                    }
                }
                "getUsageStatsForRange" -> {
                    try {
                        // Custom time range in milliseconds
                        val startTime = call.argument<Long>("startTime") ?: 0L
                        val endTime = call.argument<Long>("endTime") ?: System.currentTimeMillis()
                        val usageStats = getUsageStatsForRange(startTime, endTime)
                        result.success(usageStats)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to get usage stats for range", e)
                        result.error("ERROR", "Failed to get usage stats: ${e.message}", null)
                    }
                }
                "hasUsagePermission" -> {
                    result.success(hasUsageStatsPermission())
                }
                "openUsageSettings" -> {
                    openUsageAccessSettings()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Intervention channel
        val interventionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTERVENTION_CHANNEL)
        
        // Set MethodChannel reference in BOTH services for event push
        AppMonitorService.methodChannel = interventionChannel
        AppAccessibilityService.methodChannel = interventionChannel
        
        interventionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                // Accessibility Service methods
                "hasAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    openAccessibilitySettings()
                    result.success(true)
                }
                "isAccessibilityServiceRunning" -> {
                    result.success(AppAccessibilityService.isServiceRunning())
                }
                // Battery Optimization methods
                "isBatteryOptimizationDisabled" -> {
                    result.success(isBatteryOptimizationDisabled())
                }
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }
                // Monitoring methods (fallback polling service)
                "startMonitoring" -> {
                    try {
                        // Ensure MethodChannel is set before starting service
                        AppMonitorService.methodChannel = interventionChannel
                        
                        // If accessibility service is enabled, it handles everything
                        // Otherwise, start the polling fallback service
                        if (!isAccessibilityServiceEnabled()) {
                            AppMonitorService.startService(this@MainActivity)
                            Log.d(TAG, "Intervention monitoring started (polling fallback)")
                        } else {
                            Log.d(TAG, "Accessibility service enabled, no polling needed")
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start monitoring service", e)
                        result.error("ERROR", "Failed to start monitoring: ${e.message}", null)
                    }
                }
                "stopMonitoring" -> {
                    try {
                        AppMonitorService.stopService(this@MainActivity)
                        Log.d(TAG, "Intervention monitoring stopped")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to stop monitoring service", e)
                        result.error("ERROR", "Failed to stop monitoring: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
    
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
        }
    }
    
    private fun hasUsageStatsPermission(): Boolean {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - (60 * 1000) // Last minute
        
        // Try queryEvents first - this is more reliable for permission check
        return try {
            val events = usageStatsManager.queryEvents(startTime, endTime)
            // If we can query events without exception, permission is granted
            // Some devices return empty events but still have permission
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )
            events != null || (stats != null && stats.isNotEmpty())
        } catch (e: SecurityException) {
            false
        }
    }
    
    private fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        startActivity(intent)
    }
    
    /**
     * PRIMARY METHOD: Calculate foreground time using raw UsageEvents
     * This is identical to how Digital Wellbeing tracks app usage.
     * 
     * It tracks ACTIVITY_RESUMED → ACTIVITY_PAUSED pairs to calculate
     * exact foreground duration for ALL apps including Instagram, TikTok, etc.
     * 
     * IMPORTANT: This method strictly clips all durations to the [startTime, endTime] window.
     * If an app was opened before startTime (e.g., before midnight), only the time
     * AFTER startTime is counted.
     */
    private fun getEventBasedUsage(
        usageStatsManager: UsageStatsManager,
        startTime: Long,
        endTime: Long
    ): Map<String, EventUsageData> {
        val usageData = mutableMapOf<String, EventUsageData>()
        val activeApps = mutableMapOf<String, Long>() // packageName -> resumeTimestamp (already clipped to startTime)
        
        Log.d(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d(TAG, "📊 Querying events from ${Date(startTime)} to ${Date(endTime)}")
        Log.d(TAG, "⚠️ STRICT MODE: Only counting time within this window!")
        
        // Query events slightly before startTime to catch apps that were already open at midnight
        // We query from 1 hour before to find RESUMED events that didn't have a PAUSED before startTime
        val queryStartTime = startTime - (60 * 60 * 1000L) // 1 hour buffer
        val usageEvents = usageStatsManager.queryEvents(queryStartTime, endTime)
        val event = UsageEvents.Event()
        
        var totalEvents = 0
        var resumeEvents = 0
        var pauseEvents = 0
        var clippedSessions = 0
        
        // Track apps that were active before our window started (for clipping)
        val appsActiveBeforeWindow = mutableMapOf<String, Long>()
        
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            totalEvents++
            
            val packageName = event.packageName ?: continue
            val eventTime = event.timeStamp
            
            when (event.eventType) {
                // App came to foreground
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    resumeEvents++
                    
                    if (eventTime < startTime) {
                        // This RESUMED event is BEFORE our window (e.g., before midnight)
                        // Track it so we can clip the duration when PAUSED comes
                        appsActiveBeforeWindow[packageName] = eventTime
                    } else {
                        // Normal case: RESUMED within our time window
                        activeApps[packageName] = eventTime
                        
                        // Initialize usage data if first time seeing this app
                        if (!usageData.containsKey(packageName)) {
                            usageData[packageName] = EventUsageData(
                                totalTime = 0L,
                                lastUsed = eventTime,
                                launchCount = 0
                            )
                        }
                        
                        // Increment launch count (only for launches within our window)
                        usageData[packageName] = usageData[packageName]!!.copy(
                            launchCount = usageData[packageName]!!.launchCount + 1,
                            lastUsed = maxOf(usageData[packageName]!!.lastUsed, eventTime)
                        )
                    }
                }
                
                // App left foreground
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    pauseEvents++
                    
                    // Check if this app was resumed before our window started
                    val resumedBeforeWindow = appsActiveBeforeWindow.remove(packageName)
                    val resumeTime = activeApps.remove(packageName)
                    
                    // Skip PAUSED events that happen before our window
                    if (eventTime < startTime) {
                        continue
                    }
                    
                    val effectiveResumeTime: Long?
                    val wasClipped: Boolean
                    
                    when {
                        resumeTime != null -> {
                            // Normal case: both RESUMED and PAUSED within our window
                            effectiveResumeTime = resumeTime
                            wasClipped = false
                        }
                        resumedBeforeWindow != null -> {
                            // App was opened BEFORE our window (e.g., before midnight)
                            // Clip the start time to our window boundary (midnight)
                            effectiveResumeTime = startTime
                            wasClipped = true
                            clippedSessions++
                            Log.d(TAG, "✂️ Clipping session for $packageName: was opened at ${Date(resumedBeforeWindow)}, counting from ${Date(startTime)}")
                        }
                        else -> {
                            // Orphan PAUSED without matching RESUMED - skip
                            effectiveResumeTime = null
                            wasClipped = false
                        }
                    }
                    
                    if (effectiveResumeTime != null) {
                        val duration = eventTime - effectiveResumeTime
                        
                        // Only count positive durations (sanity check)
                        if (duration > 0) {
                            val existing = usageData[packageName]
                            if (existing != null) {
                                usageData[packageName] = existing.copy(
                                    totalTime = existing.totalTime + duration,
                                    lastUsed = maxOf(existing.lastUsed, eventTime)
                                )
                            } else {
                                usageData[packageName] = EventUsageData(
                                    totalTime = duration,
                                    lastUsed = eventTime,
                                    launchCount = if (wasClipped) 0 else 1 // Don't count as launch if clipped
                                )
                            }
                        }
                    }
                }
                
                // Also handle MOVE_TO_FOREGROUND/BACKGROUND for older Android versions
                1 -> { // MOVE_TO_FOREGROUND (value = 1)
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        if (eventTime >= startTime) {
                            activeApps[packageName] = eventTime
                        } else {
                            appsActiveBeforeWindow[packageName] = eventTime
                        }
                    }
                }
                2 -> { // MOVE_TO_BACKGROUND (value = 2)
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        if (eventTime < startTime) continue
                        
                        val resumedBeforeWindow = appsActiveBeforeWindow.remove(packageName)
                        val resumeTime = activeApps.remove(packageName)
                        
                        val effectiveResumeTime = when {
                            resumeTime != null -> resumeTime
                            resumedBeforeWindow != null -> startTime
                            else -> null
                        }
                        
                        if (effectiveResumeTime != null) {
                            val duration = eventTime - effectiveResumeTime
                            if (duration > 0) {
                                val existing = usageData[packageName]
                                if (existing != null) {
                                    usageData[packageName] = existing.copy(
                                        totalTime = existing.totalTime + duration
                                    )
                                } else {
                                    usageData[packageName] = EventUsageData(
                                        totalTime = duration,
                                        lastUsed = eventTime,
                                        launchCount = 1
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Handle apps still in foreground (currently open)
        // Also need to handle apps that were opened before our window and are STILL open
        val currentTime = minOf(System.currentTimeMillis(), endTime)
        
        // First, handle apps resumed WITHIN our window that are still active
        for ((packageName, resumeTime) in activeApps) {
            val duration = currentTime - resumeTime
            if (duration > 0) {
                val existing = usageData[packageName]
                if (existing != null) {
                    usageData[packageName] = existing.copy(
                        totalTime = existing.totalTime + duration,
                        lastUsed = currentTime
                    )
                } else {
                    usageData[packageName] = EventUsageData(
                        totalTime = duration,
                        lastUsed = currentTime,
                        launchCount = 1
                    )
                }
            }
        }
        
        // Then, handle apps that were opened BEFORE our window and are STILL open (no PAUSED yet)
        for ((packageName, _) in appsActiveBeforeWindow) {
            // These apps were opened before startTime and never paused
            // Count time from startTime (midnight) to now
            val duration = currentTime - startTime
            if (duration > 0) {
                clippedSessions++
                Log.d(TAG, "✂️ App $packageName still active from before window, counting ${duration / 60000}min from ${Date(startTime)}")
                val existing = usageData[packageName]
                if (existing != null) {
                    usageData[packageName] = existing.copy(
                        totalTime = existing.totalTime + duration,
                        lastUsed = currentTime
                    )
                } else {
                    usageData[packageName] = EventUsageData(
                        totalTime = duration,
                        lastUsed = currentTime,
                        launchCount = 0 // Don't count as launch since it started before our window
                    )
                }
            }
        }
        
        Log.d(TAG, "📈 Event Stats: total=$totalEvents, resumed=$resumeEvents, paused=$pauseEvents")
        Log.d(TAG, "✂️ Clipped sessions (started before window): $clippedSessions")
        Log.d(TAG, "📱 Apps with usage: ${usageData.size}")
        
        // Log top apps for debugging
        usageData.entries
            .sortedByDescending { it.value.totalTime }
            .take(10)
            .forEach { (pkg, data) ->
                val minutes = data.totalTime / (1000 * 60)
                Log.d(TAG, "  ✓ $pkg: ${minutes}min (${data.launchCount} opens)")
            }
        
        return usageData
    }
    
    /**
     * FALLBACK METHOD: Get aggregated stats (less accurate but useful for some data)
     */
    private fun getAggregatedStats(
        usageStatsManager: UsageStatsManager,
        startTime: Long,
        endTime: Long
    ): Map<String, Long> {
        val result = mutableMapOf<String, Long>()
        
        try {
            val stats = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
            stats?.forEach { (packageName, usageStats) ->
                if (usageStats.totalTimeInForeground > 0) {
                    result[packageName] = usageStats.totalTimeInForeground
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get aggregated stats: ${e.message}")
        }
        
        return result
    }
    
    /**
     * Main entry point: Fetch usage statistics using EVENT-BASED tracking
     * This is the Digital Wellbeing method that captures ALL apps.
     * 
     * @param mode Time window mode:
     *   - "today": Midnight to now (resets at 12:00 AM local time)
     *   - "rolling24h": Now - 24 hours → Now (like Digital Wellbeing's rolling view)
     *   - "week": Last 7 days
     */
    private fun getUsageStats(mode: String = "today"): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val packageManager = packageManager
        
        val endTime = System.currentTimeMillis()
        val startTime: Long
        val windowLabel: String
        
        when (mode) {
            "rolling24h" -> {
                // ROLLING 24-HOUR WINDOW - Exactly like Digital Wellbeing
                // If it's 2:10 PM now, this covers Yesterday 2:10 PM → Today 2:10 PM
                startTime = endTime - (24 * 60 * 60 * 1000L)
                windowLabel = "Rolling 24h"
            }
            "week" -> {
                // Last 7 days
                startTime = endTime - (7 * 24 * 60 * 60 * 1000L)
                windowLabel = "Last 7 days"
            }
            else -> {
                // "today" - Midnight to now (calendar day)
                val calendar = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                startTime = calendar.timeInMillis
                windowLabel = "Today (midnight → now)"
            }
        }
        
        Log.d(TAG, "")
        Log.d(TAG, "🚀 getUsageStats() called with mode: $mode")
        Log.d(TAG, "⏰ Window: $windowLabel")
        Log.d(TAG, "📅 Range: ${Date(startTime)} → ${Date(endTime)}")
        
        // PRIMARY: Get event-based usage (Digital Wellbeing method)
        // This is the ONLY reliable source for strict time window tracking
        val eventUsage = getEventBasedUsage(usageStatsManager, startTime, endTime)
        
        // FALLBACK: Get aggregated stats ONLY for apps not captured by events
        // NOTE: Aggregated stats are NOT reliable for strict time windows!
        // They may include data from outside the requested range.
        // We only use them as a fallback for apps with zero event data.
        val aggregatedUsage = if (mode == "today") {
            // For "today" mode, DON'T use aggregated stats - they're unreliable for strict midnight cutoff
            Log.d(TAG, "⚠️ Today mode: Skipping aggregated stats (unreliable for strict time windows)")
            emptyMap()
        } else {
            getAggregatedStats(usageStatsManager, startTime, endTime)
        }
        
        // Merge all package names
        val allPackages = mutableSetOf<String>()
        allPackages.addAll(eventUsage.keys)
        allPackages.addAll(aggregatedUsage.keys)
        
        Log.d(TAG, "📦 Total unique packages: ${allPackages.size}")
        Log.d(TAG, "📊 Event-based apps: ${eventUsage.size}, Aggregated apps: ${aggregatedUsage.size}")
        
        val usageList = ArrayList<Map<String, Any>>()
        
        for (packageName in allPackages) {
            try {
                // Get time from both sources
                val eventData = eventUsage[packageName]
                val aggregatedTime = aggregatedUsage[packageName] ?: 0L
                
                // STRICT: Prefer event-based data ALWAYS
                // Only fall back to aggregated if NO event data exists
                // NEVER take maxOf() - this was causing inflated numbers!
                val totalTimeInMs = when {
                    eventData != null -> eventData.totalTime // Always prefer events - they respect time boundaries
                    else -> aggregatedTime // Fallback only if no events (and not in "today" mode)
                }
                
                // Skip apps with zero or negligible usage (less than 1 second)
                if (totalTimeInMs < 1000) continue
                
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                
                // Determine if it's a true system app (no launcher icon)
                val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                                  (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                val hasLauncherIcon = launchIntent != null
                val isTrueSystemApp = isSystemApp && !hasLauncherIcon
                
                val appName = packageManager.getApplicationLabel(appInfo).toString()
                val lastTimeUsed = eventData?.lastUsed ?: 0L
                val launchCount = eventData?.launchCount ?: 0
                
                // Calculate time components
                val hours = totalTimeInMs / (1000 * 60 * 60)
                val minutes = (totalTimeInMs % (1000 * 60 * 60)) / (1000 * 60)
                val seconds = (totalTimeInMs % (1000 * 60)) / 1000
                
                val usageMap = mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "totalTimeInForeground" to totalTimeInMs,
                    "lastTimeUsed" to lastTimeUsed,
                    "launchCount" to launchCount,
                    "hours" to hours,
                    "minutes" to minutes,
                    "seconds" to seconds,
                    "formattedTime" to formatTime(hours, minutes, seconds),
                    "isSystemApp" to isTrueSystemApp
                )
                
                usageList.add(usageMap)
                
            } catch (e: PackageManager.NameNotFoundException) {
                // App was uninstalled, skip
                continue
            }
        }
        
        // Sort by usage time (highest first)
        val sortedList = usageList.sortedByDescending { it["totalTimeInForeground"] as Long }
        
        Log.d(TAG, "✅ Returning ${sortedList.size} apps with usage data")
        Log.d(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        return sortedList
    }
    
    /**
     * Fetch usage statistics for a custom time range.
     * This allows querying any arbitrary time window.
     * 
     * @param startTime Start of the range in milliseconds since epoch
     * @param endTime End of the range in milliseconds since epoch
     */
    private fun getUsageStatsForRange(startTime: Long, endTime: Long): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val packageManager = packageManager
        
        Log.d(TAG, "")
        Log.d(TAG, "🚀 getUsageStatsForRange() called")
        Log.d(TAG, "📅 Custom Range: ${Date(startTime)} → ${Date(endTime)}")
        
        // PRIMARY: Get event-based usage (Digital Wellbeing method)
        // This is the ONLY reliable source for strict time window tracking
        val eventUsage = getEventBasedUsage(usageStatsManager, startTime, endTime)
        
        // For custom ranges, we also skip aggregated stats to ensure strict time boundaries
        // Aggregated stats are known to return data outside the requested time window
        Log.d(TAG, "⚠️ Custom range: Using ONLY event-based data for strict time boundaries")
        
        // Merge all package names (only from events for strict mode)
        val allPackages = mutableSetOf<String>()
        allPackages.addAll(eventUsage.keys)
        
        Log.d(TAG, "📦 Total unique packages: ${allPackages.size}")
        
        val usageList = ArrayList<Map<String, Any>>()
        
        for (packageName in allPackages) {
            try {
                val eventData = eventUsage[packageName]
                
                // STRICT: Only use event-based data for accurate time boundaries
                val totalTimeInMs = eventData?.totalTime ?: 0L
                
                if (totalTimeInMs < 1000) continue
                
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                
                val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                                  (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                val hasLauncherIcon = launchIntent != null
                val isTrueSystemApp = isSystemApp && !hasLauncherIcon
                
                val appName = packageManager.getApplicationLabel(appInfo).toString()
                val lastTimeUsed = eventData?.lastUsed ?: 0L
                val launchCount = eventData?.launchCount ?: 0
                
                val hours = totalTimeInMs / (1000 * 60 * 60)
                val minutes = (totalTimeInMs % (1000 * 60 * 60)) / (1000 * 60)
                val seconds = (totalTimeInMs % (1000 * 60)) / 1000
                
                val usageMap = mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "totalTimeInForeground" to totalTimeInMs,
                    "lastTimeUsed" to lastTimeUsed,
                    "launchCount" to launchCount,
                    "hours" to hours,
                    "minutes" to minutes,
                    "seconds" to seconds,
                    "formattedTime" to formatTime(hours, minutes, seconds),
                    "isSystemApp" to isTrueSystemApp
                )
                
                usageList.add(usageMap)
                
            } catch (e: PackageManager.NameNotFoundException) {
                continue
            }
        }
        
        val sortedList = usageList.sortedByDescending { it["totalTimeInForeground"] as Long }
        
        Log.d(TAG, "✅ Returning ${sortedList.size} apps with usage data (custom range)")
        Log.d(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        return sortedList
    }
    
    private fun formatTime(hours: Long, minutes: Long, seconds: Long): String {
        return when {
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m ${seconds}s"
            else -> "${seconds}s"
        }
    }
    
    /**
     * Data class to hold event-based usage information
     */
    data class EventUsageData(
        val totalTime: Long,
        val lastUsed: Long,
        val launchCount: Int
    )
    
    // ==================== Accessibility Service Methods ====================
    
    /**
     * Check if our accessibility service is enabled
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val accessibilityManager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabledServices = accessibilityManager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_GENERIC
        )
        
        val componentName = ComponentName(this, AppAccessibilityService::class.java)
        
        for (service in enabledServices) {
            val enabledServiceComponent = service.resolveInfo.serviceInfo
            if (enabledServiceComponent.packageName == componentName.packageName &&
                enabledServiceComponent.name == componentName.className) {
                return true
            }
        }
        return false
    }
    
    /**
     * Open accessibility settings for user to enable our service
     */
    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }
    
    // ==================== Battery Optimization Methods ====================
    
    /**
     * Check if our app is exempt from battery optimization
     */
    private fun isBatteryOptimizationDisabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true // Not applicable before Android M
        }
    }
    
    /**
     * Request battery optimization exemption
     * This shows a system dialog asking user to exempt the app
     */
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    // Direct request (shows system dialog)
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    // Fallback: Open battery optimization settings
                    Log.w(TAG, "Direct battery exemption request failed, opening settings", e)
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                    } catch (e2: Exception) {
                        Log.e(TAG, "Failed to open battery settings", e2)
                    }
                }
            }
        }
    }
}
