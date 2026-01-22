import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../services/debug_log_service.dart';
import 'notification_service.dart';
import '../widgets/intervention_overlay.dart';

/// Callback type for app launch events
typedef AppLaunchCallback = void Function(String packageName, String appName);

/// Context provider function type
typedef ContextProvider = BuildContext? Function();

/// Service for managing app launch interventions
class AppInterventionService {
  static final AppInterventionService _instance = AppInterventionService._internal();
  factory AppInterventionService() => _instance;
  AppInterventionService._internal();

  static const MethodChannel _channel = MethodChannel('com.brainbud.intervention/channel');
  
  bool _initialized = false;
  AppLaunchCallback? _onAppLaunchCallback;
  Timer? _monitoringTimer;
  ContextProvider? _contextProvider;

  /// Initialize the intervention service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Check if overlay permission is granted
      final hasPermission = await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
      
      if (!hasPermission) {
        debugLog.warning('InterventionService', 'Overlay permission not granted');
      }

      // Set up method channel handler to receive app launch events
      _channel.setMethodCallHandler(_handleMethodCall);

      _initialized = true;
      debugLog.info('InterventionService', 'Initialized');
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to initialize: $e');
    }
  }

  /// Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAppLaunch':
        try {
          // Parse arguments - Android sends a Map
          final args = call.arguments as Map<dynamic, dynamic>?;
          final packageName = args?['packageName'] as String?;
          
          if (packageName != null) {
            debugLog.info('InterventionService', 'App launch detected (event push): $packageName');
            
            // Get app name from package name
            final appName = _getAppNameFromPackage(packageName);
            
            // Unified handler: triggers both notification and intervention overlay
            await _handleAppLaunch(packageName, appName);
          }
        } catch (e) {
          debugLog.error('InterventionService', 'Error handling onAppLaunch: $e');
        }
        break;
      default:
        debugLog.warning('InterventionService', 'Unknown method: ${call.method}');
    }
  }

  /// Check if app should trigger notification (all social media apps)
  bool _shouldNotifyForApp(String packageName) {
    final lowerPackage = packageName.toLowerCase();
    // Check for all social media apps
    return lowerPackage.contains('instagram') ||
           lowerPackage.contains('facebook') ||
           lowerPackage.contains('messenger') ||
           lowerPackage.contains('whatsapp') ||
           lowerPackage.contains('telegram') ||
           lowerPackage.contains('snapchat') ||
           lowerPackage.contains('tiktok') ||
           lowerPackage.contains('musically') ||
           lowerPackage.contains('twitter') ||
           lowerPackage.contains('linkedin') ||
           lowerPackage.contains('reddit') ||
           lowerPackage.contains('discord') ||
           lowerPackage.contains('pinterest') ||
           lowerPackage.contains('youtube');
  }

  /// Unified handler for app launch detection
  /// Triggers both notifications and intervention overlay (piggyback system)
  Future<void> _handleAppLaunch(String packageName, String appName) async {
    // Check if it's a social media app
    final shouldNotify = _shouldNotifyForApp(packageName);
    
    if (!shouldNotify) {
      // Not a social media app, just increment attempt and return
      await incrementLaunchAttempt(packageName);
      _onAppLaunchCallback?.call(packageName, appName);
      return;
    }
    
    // Send notification
    final notificationService = NotificationService();
    await notificationService.showAppLaunchNotification(
      appName: appName,
      packageName: packageName,
    );
    
    // Trigger intervention overlay (piggyback on notification system)
    final enabled = await areInterventionsEnabled();
    if (enabled) {
      final context = _contextProvider?.call();
      if (context != null) {
        try {
          await InterventionOverlay.showIntervention(context, packageName, appName);
        } catch (e) {
          debugLog.error('InterventionService', 'Failed to show intervention overlay: $e');
        }
      } else {
        debugLog.warning('InterventionService', 'No context available for overlay');
      }
    }
    
    // Increment launch attempt
    await incrementLaunchAttempt(packageName);
    
    // Call callback for backward compatibility
    _onAppLaunchCallback?.call(packageName, appName);
  }

  /// Get app name from package name
  String _getAppNameFromPackage(String packageName) {
    // Common app name mappings
    final appNameMap = {
      'com.instagram.android': 'Instagram',
      'com.facebook.katana': 'Facebook',
      'com.facebook.orca': 'Messenger',
      'com.whatsapp': 'WhatsApp',
      'org.telegram.messenger': 'Telegram',
      'com.snapchat.android': 'Snapchat',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.twitter.android': 'Twitter',
      'com.linkedin.android': 'LinkedIn',
      'com.reddit.frontpage': 'Reddit',
      'com.discord': 'Discord',
      'com.pinterest': 'Pinterest',
      'com.google.android.youtube': 'YouTube',
    };
    
    // Return mapped name or extract from package
    if (appNameMap.containsKey(packageName)) {
      return appNameMap[packageName]!;
    }
    
    // Extract app name from package (e.g., com.instagram.android -> Instagram)
    final parts = packageName.split('.');
    if (parts.length >= 2) {
      // Try to get a meaningful name from package
      final lastPart = parts.last;
      if (lastPart != 'android' && lastPart.length > 1) {
        return lastPart.substring(0, 1).toUpperCase() + lastPart.substring(1);
      }
      // Fallback to second-to-last part
      if (parts.length >= 3) {
        final secondLast = parts[parts.length - 2];
        return secondLast.substring(0, 1).toUpperCase() + secondLast.substring(1);
      }
    }
    return packageName;
  }

  /// Set callback for app launch events
  void setAppLaunchCallback(AppLaunchCallback? callback) {
    _onAppLaunchCallback = callback;
  }

  /// Set context provider for showing intervention overlay
  void setContextProvider(ContextProvider provider) {
    _contextProvider = provider;
  }

  /// Check if interventions are enabled
  Future<bool> areInterventionsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('interventions_enabled') ?? true; // Default enabled
  }

  /// Enable or disable interventions
  Future<void> setInterventionsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interventions_enabled', enabled);
    debugLog.info('InterventionService', 'Interventions ${enabled ? "enabled" : "disabled"}');
  }

  /// Start monitoring app launches (event push with fallback polling)
  Future<void> startMonitoring() async {
    if (!_initialized) await initialize();
    
    final enabled = await areInterventionsEnabled();
    if (!enabled) {
      stopMonitoring();
      return;
    }

    try {
      // Start native foreground service
      await _channel.invokeMethod('startMonitoring');
      
      // Stop existing timer if any
      _monitoringTimer?.cancel();

      // Start fallback polling (checks SharedPreferences if event push fails)
      // This ensures we catch events even if MethodChannel push doesn't work
      _monitoringTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        await _checkForAppLaunches();
      });

      debugLog.info('InterventionService', 'Started monitoring (event push + fallback polling)');
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to start monitoring: $e');
    }
  }

  /// Stop monitoring app launches
  Future<void> stopMonitoring() async {
    try {
      // Stop native service
      await _channel.invokeMethod('stopMonitoring');
      
      // Stop Flutter timer
      _monitoringTimer?.cancel();
      _monitoringTimer = null;
      
      debugLog.info('InterventionService', 'Stopped monitoring');
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to stop monitoring: $e');
    }
  }

  /// Check for recent app launches (fallback: reads from SharedPreferences)
  Future<void> _checkForAppLaunches() async {
    try {
      final enabled = await areInterventionsEnabled();
      if (!enabled) {
        stopMonitoring();
        return;
      }

      // Check SharedPreferences for new app detections
      final prefs = await SharedPreferences.getInstance();
      final newAppDetected = prefs.getBool('new_app_detected') ?? false;
      
      if (newAppDetected) {
        final packageName = prefs.getString('last_detected_package');
        // Android stores as Long, Flutter reads as String and parses
        final lastDetectionTimeStr = prefs.getString('last_detection_time');
        final lastDetectionTime = lastDetectionTimeStr != null 
            ? int.tryParse(lastDetectionTimeStr) ?? 0 
            : 0;
        
        if (packageName != null && lastDetectionTime > 0) {
          // Check if this is a new detection (not the same one we already handled)
          final lastHandledTimeStr = prefs.getString('last_handled_detection_time');
          final lastHandledTime = lastHandledTimeStr != null 
              ? int.tryParse(lastHandledTimeStr) ?? 0 
              : 0;
          
          if (lastDetectionTime > lastHandledTime) {
            // Mark as handled
            await prefs.setString('last_handled_detection_time', lastDetectionTime.toString());
            await prefs.setBool('new_app_detected', false);
            
            // Get app name
            final appName = _getAppNameFromPackage(packageName);
            
            // Unified handler: triggers both notification and intervention overlay
            await _handleAppLaunch(packageName, appName);
            
            debugLog.info('InterventionService', 'App launch detected (fallback): $packageName');
          }
        }
      }
    } catch (e) {
      debugLog.error('InterventionService', 'Error checking app launches: $e');
    }
  }

  /// Request overlay permission
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to request overlay permission: $e');
    }
  }

  /// Check if overlay permission is granted
  Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (e) {
      return false;
    }
  }

  // ==================== Accessibility Service Methods ====================

  /// Check if accessibility service is enabled
  Future<bool> hasAccessibilityPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to check accessibility permission: $e');
      return false;
    }
  }

  /// Request user to enable accessibility service
  Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to request accessibility permission: $e');
    }
  }

  /// Check if accessibility service is currently running
  Future<bool> isAccessibilityServiceRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityServiceRunning') ?? false;
    } catch (e) {
      return false;
    }
  }

  // ==================== Battery Optimization Methods ====================

  /// Check if battery optimization is disabled for our app
  Future<bool> isBatteryOptimizationDisabled() async {
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimizationDisabled') ?? false;
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to check battery optimization: $e');
      return false;
    }
  }

  /// Request battery optimization exemption
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      debugLog.error('InterventionService', 'Failed to request battery exemption: $e');
    }
  }

  // ==================== Permission Check Helpers ====================

  /// Check all required permissions and return status
  Future<Map<String, bool>> checkAllPermissions() async {
    return {
      'usageAccess': true, // Checked elsewhere
      'overlay': await hasOverlayPermission(),
      'accessibility': await hasAccessibilityPermission(),
      'batteryOptimization': await isBatteryOptimizationDisabled(),
    };
  }

  /// Get app launch attempts for today
  Future<Map<String, int>> getLaunchAttemptsToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final key = 'launch_attempts_$today';
    
    final data = prefs.getString(key);
    if (data == null) return {};

    try {
      return Map<String, int>.from(
        (jsonDecode(data) as Map).map((k, v) => MapEntry(k.toString(), v as int))
      );
    } catch (e) {
      return {};
    }
  }

  /// Increment launch attempt for an app
  Future<void> incrementLaunchAttempt(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final key = 'launch_attempts_$today';
    
    final attempts = await getLaunchAttemptsToday();
    attempts[packageName] = (attempts[packageName] ?? 0) + 1;
    
    await prefs.setString(key, jsonEncode(attempts));
  }

  /// Get total launch attempts for last 24 hours
  Future<int> getTotalAttemptsLast24h(String packageName) async {
    final attempts = await getLaunchAttemptsToday();
    return attempts[packageName] ?? 0;
  }
}

