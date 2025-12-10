import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'usage_stats_service.dart';
import 'debug_log_service.dart';

/// Service for monitoring usage and triggering notifications
class UsageMonitorService {
  static final UsageMonitorService _instance = UsageMonitorService._internal();
  factory UsageMonitorService() => _instance;
  UsageMonitorService._internal();

  static const String taskName = 'brainBudUsageMonitor';
  static const String moodCheckTaskName = 'brainBudMoodCheck';

  /// Initialize the background monitoring service
  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Register periodic task to check usage (every 30 minutes)
    await Workmanager().registerPeriodicTask(
      taskName,
      moodCheckTaskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );

    debugLog.info('UsageMonitor', 'Background monitoring initialized');
  }

  /// Cancel all background tasks
  Future<void> cancelAll() async {
    await Workmanager().cancelByUniqueName(taskName);
    debugLog.info('UsageMonitor', 'Background monitoring cancelled');
  }
}

/// Background callback dispatcher
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugLog.info('UsageMonitor', 'Background task executed: $task');

    try {
      if (task == UsageMonitorService.moodCheckTaskName) {
        await _checkMoodChange();
      } else if (task == 'dailySummary') {
        await _sendDailySummary();
      }
      return Future.value(true);
    } catch (e) {
      debugLog.error('UsageMonitor', 'Background task failed: $e');
      return Future.value(false);
    }
  });
}

/// Check if mood has changed and send notification
Future<void> _checkMoodChange() async {
  try {
    // Get current usage stats
    final stats = await UsageStatsService.getUsageStats();
    final socialMediaTime = stats
        .where((app) => app.isSocialMediaApp() && !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

    final socialMinutes = socialMediaTime ~/ (1000 * 60);

    // Determine current mood
    String currentMood;
    if (socialMinutes < 30) {
      currentMood = 'happy';
    } else if (socialMinutes < 120) {
      currentMood = 'neutral';
    } else {
      currentMood = 'sad';
    }

    // Get last known mood from storage
    final prefs = await SharedPreferences.getInstance();
    final lastMood = prefs.getString('last_known_mood');
    final lastSocialMinutes = prefs.getInt('last_known_social_minutes') ?? 0;

    // Update stored values
    await prefs.setString('last_known_mood', currentMood);
    await prefs.setInt('last_known_social_minutes', socialMinutes);

    // If mood changed, send notification
    if (lastMood != null && lastMood != currentMood) {
      final notificationService = NotificationService();
      await notificationService.initialize();

      String message;
      if (currentMood == 'happy') {
        if (socialMinutes == 0) {
          message = "No social media today! I'm so proud of you! 🌟";
        } else {
          message = "Only ${socialMinutes}m on social media. Great balance! 🎉";
        }
      } else if (currentMood == 'neutral') {
        final hours = socialMinutes ~/ 60;
        final mins = socialMinutes % 60;
        message = "${hours}h ${mins}m on social media. Maybe take a break? 🤔";
      } else {
        final hours = socialMinutes ~/ 60;
        final mins = socialMinutes % 60;
        message = "${hours}h ${mins}m scrolling... I miss the real you 😢";
      }

      await notificationService.showMoodChangeNotification(
        mood: currentMood,
        message: message,
        socialMediaMinutes: socialMinutes,
      );

      debugLog.success('UsageMonitor', 'Mood change notification sent: $lastMood → $currentMood');
    }

    // Also check if approaching threshold (warn at 25m and 1h 45m)
    if (socialMinutes == 25 && lastSocialMinutes < 25) {
      final notificationService = NotificationService();
      await notificationService.initialize();
      await notificationService.showMoodChangeNotification(
        mood: 'approaching_neutral',
        message: "You're 5 minutes away from 30m of social media. Your Brain Bud wants you to take a break!",
        socialMediaMinutes: socialMinutes,
      );
    } else if (socialMinutes == 105 && lastSocialMinutes < 105) {
      final notificationService = NotificationService();
      await notificationService.initialize();
      await notificationService.showMoodChangeNotification(
        mood: 'approaching_sad',
        message: "You're 15 minutes away from 2h of social media. Time for a break!",
        socialMediaMinutes: socialMinutes,
      );
    }
  } catch (e) {
    debugLog.error('UsageMonitor', 'Failed to check mood change: $e');
  }
}

/// Send daily summary notification
Future<void> _sendDailySummary() async {
  try {
    final stats = await UsageStatsService.getUsageStats();
    final totalTime = stats
        .where((app) => !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);
    
    final socialMediaTime = stats
        .where((app) => app.isSocialMediaApp() && !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

    final totalMinutes = totalTime ~/ (1000 * 60);
    final socialMinutes = socialMediaTime ~/ (1000 * 60);

    // Determine mood
    String mood;
    if (socialMinutes < 30) {
      mood = 'happy';
    } else if (socialMinutes < 120) {
      mood = 'neutral';
    } else {
      mood = 'sad';
    }

    final notificationService = NotificationService();
    await notificationService.initialize();

    await notificationService.showDailySummaryNotification(
      totalScreenTimeMinutes: totalMinutes,
      socialMediaMinutes: socialMinutes,
      mood: mood,
    );

    debugLog.success('UsageMonitor', 'Daily summary notification sent');
  } catch (e) {
    debugLog.error('UsageMonitor', 'Failed to send daily summary: $e');
  }
}

