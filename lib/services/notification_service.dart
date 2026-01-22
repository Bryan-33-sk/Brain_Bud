import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';
import 'debug_log_service.dart';

/// Service for managing local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification channel IDs
  static const String moodChannelId = 'brain_bud_mood_alerts';
  static const String summaryChannelId = 'brain_bud_daily_summary';
  static const String appLaunchChannelId = 'brain_bud_app_launch';

  /// Request notification permission (Android 13+)
  Future<bool> requestNotificationPermission() async {
    // Check if running on Android
    if (Platform.isAndroid) {
      try {
        // For Android 13+ (API 33+), request POST_NOTIFICATIONS
        final status = await Permission.notification.request();
        debugLog.info(
            'NotificationService', 'Notification permission status: $status');
        return status.isGranted;
      } catch (e) {
        debugLog.error('NotificationService',
            'Failed to request notification permission: $e');
        // Continue anyway - older Android versions don't need it
        return true;
      }
    }

    // For iOS, permissions are handled by DarwinInitializationSettings
    // For older Android, notifications work without explicit permission
    return true;
  }

  /// Initialize the notification service
  Future<bool> initialize() async {
    if (_initialized) return true;

    // Request permission first (Android 13+)
    final hasPermission = await requestNotificationPermission();
    if (!hasPermission) {
      debugLog.warning('NotificationService', 'Notification permission denied');
      // Continue anyway - older Android versions don't need it
    }

    // Android initialization settings
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings (for future iOS support)
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final bool? initialized = await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (initialized == true) {
      await _createNotificationChannels();
      _initialized = true;
      return true;
    }

    return false;
  }

  /// Create notification channels for Android 8.0+
  Future<void> _createNotificationChannels() async {
    // Mood alerts channel
    const moodChannel = AndroidNotificationChannel(
      moodChannelId,
      'Mood Alerts',
      description: 'Notifications when your Brain Bud\'s mood changes',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Daily summary channel
    const summaryChannel = AndroidNotificationChannel(
      summaryChannelId,
      'Daily Summary',
      description: 'Daily usage summary notifications',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(moodChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(summaryChannel);

    // App launch channel
    const appLaunchChannel = AndroidNotificationChannel(
      appLaunchChannelId,
      'App Launch Alerts',
      description: 'Notifications when specific apps are opened',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(appLaunchChannel);
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - can navigate to specific screen
    // This will be handled by the app's navigation system
  }

  /// Show mood change notification
  Future<void> showMoodChangeNotification({
    required String mood,
    required String message,
    required int socialMediaMinutes,
  }) async {
    if (!_initialized) await initialize();

    // Check if mood notifications are enabled
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notifications_mood_enabled') ?? true;
    if (!enabled) return;

    // Check rate limiting (max 3 mood notifications per day)
    final lastMoodNotificationDate =
        prefs.getString('last_mood_notification_date');
    final today = DateTime.now().toIso8601String().split('T')[0];
    final moodNotificationCount =
        prefs.getInt('mood_notification_count_$today') ?? 0;

    if (lastMoodNotificationDate != today) {
      await prefs.setInt('mood_notification_count_$today', 0);
    }

    if (moodNotificationCount >= 3) return; // Rate limit reached

    // Increment counter
    await prefs.setInt(
        'mood_notification_count_$today', moodNotificationCount + 1);
    await prefs.setString('last_mood_notification_date', today);

    // Get emoji based on mood
    final emoji = mood == 'happy'
        ? '😊'
        : mood == 'neutral'
            ? '😐'
            : '😢';

    const androidDetails = AndroidNotificationDetails(
      moodChannelId,
      'Mood Alerts',
      channelDescription: 'Notifications when your Brain Bud\'s mood changes',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF7C3AED),
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      '$emoji Your Brain Bud is feeling $mood!',
      message,
      details,
    );
  }

  /// Show daily summary notification
  Future<void> showDailySummaryNotification({
    required int totalScreenTimeMinutes,
    required int socialMediaMinutes,
    required String mood,
  }) async {
    if (!_initialized) await initialize();

    // Check if summary notifications are enabled
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notifications_summary_enabled') ?? true;
    if (!enabled) return;

    // Check if we've already sent today's summary
    final lastSummaryDate = prefs.getString('last_summary_notification_date');
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (lastSummaryDate == today) return; // Already sent today

    await prefs.setString('last_summary_notification_date', today);

    // Format time
    final totalHours = totalScreenTimeMinutes ~/ 60;
    final totalMins = totalScreenTimeMinutes % 60;
    final socialHours = socialMediaMinutes ~/ 60;
    final socialMins = socialMediaMinutes % 60;

    final totalTimeStr =
        totalHours > 0 ? '${totalHours}h ${totalMins}m' : '${totalMins}m';
    final socialTimeStr =
        socialHours > 0 ? '${socialHours}h ${socialMins}m' : '${socialMins}m';

    final emoji = mood == 'happy'
        ? '😊'
        : mood == 'neutral'
            ? '😐'
            : '😢';
    final title = '$emoji Today\'s Summary';
    final body = 'Total: $totalTimeStr | Social: $socialTimeStr\n'
        'Your Brain Bud is feeling $mood!';

    const androidDetails = AndroidNotificationDetails(
      summaryChannelId,
      'Daily Summary',
      channelDescription: 'Daily usage summary notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF7C3AED),
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 + 1,
      title,
      body,
      details,
    );
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Check if notifications are enabled
  Future<bool> areMoodNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_mood_enabled') ?? true;
  }

  Future<bool> areSummaryNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_summary_enabled') ?? true;
  }

  /// Set notification preferences
  Future<void> setMoodNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_mood_enabled', enabled);
  }

  Future<void> setSummaryNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_summary_enabled', enabled);
  }

  Future<bool> areAppLaunchNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_app_launch_enabled') ?? true;
  }

  Future<void> setAppLaunchNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_app_launch_enabled', enabled);
  }

  /// Set daily summary time (hour in 24-hour format)
  Future<void> setDailySummaryTime(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_summary_hour', hour);
  }

  Future<int> getDailySummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('daily_summary_hour') ?? 21; // Default 9 PM
  }

  /// Show achievement unlock notification
  Future<void> showAchievementNotification({
    required String title,
    required String description,
    required String icon,
  }) async {
    if (!_initialized) await initialize();

    // Check if achievement notifications are enabled
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notifications_achievements_enabled') ?? true;
    if (!enabled) return;

    const androidDetails = AndroidNotificationDetails(
      moodChannelId, // Reuse mood channel for achievements
      'Mood Alerts',
      channelDescription: 'Notifications when your Brain Bud\'s mood changes',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF7C3AED),
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 + 2,
      '$icon Achievement Unlocked!',
      '$title - $description',
      details,
    );
  }

  /// Show app launch notification for specific apps (TikTok, Instagram, YouTube)
  Future<void> showAppLaunchNotification({
    required String appName,
    required String packageName,
  }) async {
    if (!_initialized) await initialize();

    // Check if app launch notifications are enabled
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notifications_app_launch_enabled') ?? true;
    if (!enabled) return;

    // Rate limiting: max 5 notifications per hour per app
    final now = DateTime.now();
    final hourKey =
        'app_launch_notification_${packageName}_${now.year}_${now.month}_${now.day}_${now.hour}';
    final count = prefs.getInt(hourKey) ?? 0;

    if (count >= 5) return; // Rate limit reached

    await prefs.setInt(hourKey, count + 1);

    // Get app emoji based on package name
    String emoji = '📱';
    final lowerPackage = packageName.toLowerCase();

    if (lowerPackage.contains('instagram')) {
      emoji = '📷';
    } else if (lowerPackage.contains('facebook')) {
      emoji = '👥';
    } else if (lowerPackage.contains('messenger')) {
      emoji = '💬';
    } else if (lowerPackage.contains('whatsapp')) {
      emoji = '💚';
    } else if (lowerPackage.contains('telegram')) {
      emoji = '✈️';
    } else if (lowerPackage.contains('snapchat')) {
      emoji = '👻';
    } else if (lowerPackage.contains('tiktok') ||
        lowerPackage.contains('musically')) {
      emoji = '🎵';
    } else if (lowerPackage.contains('twitter')) {
      emoji = '🐦';
    } else if (lowerPackage.contains('linkedin')) {
      emoji = '💼';
    } else if (lowerPackage.contains('reddit')) {
      emoji = '🤖';
    } else if (lowerPackage.contains('discord')) {
      emoji = '🎮';
    } else if (lowerPackage.contains('pinterest')) {
      emoji = '📌';
    } else if (lowerPackage.contains('youtube')) {
      emoji = '▶️';
    }

    const androidDetails = AndroidNotificationDetails(
      appLaunchChannelId,
      'App Launch Alerts',
      channelDescription: 'Notifications when specific apps are opened',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF7C3AED),
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 + 100,
      '$emoji $appName opened',
      'You just opened $appName',
      details,
    );
  }
}
