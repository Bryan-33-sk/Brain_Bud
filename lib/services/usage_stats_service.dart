import 'package:flutter/services.dart';
import 'debug_log_service.dart';

/// Time window modes for usage statistics (aligned with Digital Wellbeing)
enum UsageTimeWindow {
  /// Today from midnight to now (calendar day, resets at 12:00 AM)
  today,
  
  /// Rolling 24-hour window (now - 24h → now)
  /// This is how Digital Wellbeing calculates its main dashboard
  rolling24h,
  
  /// Last 7 days
  week,
}

/// Service for accessing native Android usage statistics via platform channels
/// 
/// This service uses the same UsageEvents API that Digital Wellbeing uses,
/// tracking ACTIVITY_RESUMED → ACTIVITY_PAUSED pairs for accurate foreground time.
class UsageStatsService {
  static const platform = MethodChannel('com.brainbud.usage_stats/channel');

  /// Check if usage stats permission is granted
  static Future<bool> hasUsagePermission() async {
    debugLog.api('UsageStatsService', 'Checking usage permission via platform channel');
    try {
      final bool hasPermission = await platform.invokeMethod('hasUsagePermission');
      debugLog.info('UsageStatsService', 'Permission check result: $hasPermission');
      return hasPermission;
    } on PlatformException catch (e) {
      debugLog.error('UsageStatsService', 'Permission check failed: ${e.message}', data: {
        'code': e.code,
        'details': e.details?.toString(),
      });
      return false;
    }
  }

  /// Open usage access settings for user to grant permission
  static Future<void> openUsageSettings() async {
    try {
      await platform.invokeMethod('openUsageSettings');
    } on PlatformException catch (e) {
      print("Error opening settings: ${e.message}");
    }
  }

  /// Fetch app usage statistics with configurable time window
  /// 
  /// [mode] - The time window to query:
  ///   - [UsageTimeWindow.today]: Midnight to now (default, calendar day)
  ///   - [UsageTimeWindow.rolling24h]: Rolling 24h window (like Digital Wellbeing)
  ///   - [UsageTimeWindow.week]: Last 7 days
  static Future<List<AppUsageInfo>> getUsageStats({
    UsageTimeWindow mode = UsageTimeWindow.today,
  }) async {
    final String modeString = switch (mode) {
      UsageTimeWindow.today => 'today',
      UsageTimeWindow.rolling24h => 'rolling24h',
      UsageTimeWindow.week => 'week',
    };
    
    debugLog.api('UsageStatsService', 'Fetching usage stats', data: {
      'mode': modeString,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    try {
      final stopwatch = Stopwatch()..start();
      final List<dynamic> result = await platform.invokeMethod(
        'getUsageStats',
        {'mode': modeString},
      );
      stopwatch.stop();
      
      final apps = result.map((data) => AppUsageInfo.fromMap(data)).toList();
      
      debugLog.success('UsageStatsService', 'Stats fetched successfully', data: {
        'mode': modeString,
        'appCount': apps.length,
        'fetchTimeMs': stopwatch.elapsedMilliseconds,
      });
      
      // Log details about the data received
      if (apps.isNotEmpty) {
        final totalTime = apps.fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);
        debugLog.data('UsageStatsService', 'Data summary', data: {
          'totalApps': apps.length,
          'totalTimeMs': totalTime,
          'totalTimeFormatted': '${totalTime ~/ (1000 * 60 * 60)}h ${(totalTime % (1000 * 60 * 60)) ~/ (1000 * 60)}m',
          'topApp': apps.first.appName,
          'topAppTime': apps.first.formattedTime,
        });
      }
      
      return apps;
    } on PlatformException catch (e) {
      debugLog.error('UsageStatsService', 'Failed to fetch usage stats', data: {
        'mode': modeString,
        'error': e.message,
        'code': e.code,
      });
      return [];
    }
  }

  /// Fetch app usage statistics for a custom time range
  /// 
  /// [startTime] - Start of the range (DateTime)
  /// [endTime] - End of the range (DateTime)
  /// 
  /// Example:
  /// ```dart
  /// // Get usage for yesterday
  /// final yesterday = DateTime.now().subtract(Duration(days: 1));
  /// final startOfYesterday = DateTime(yesterday.year, yesterday.month, yesterday.day);
  /// final endOfYesterday = startOfYesterday.add(Duration(days: 1));
  /// final stats = await UsageStatsService.getUsageStatsForRange(
  ///   startTime: startOfYesterday,
  ///   endTime: endOfYesterday,
  /// );
  /// ```
  static Future<List<AppUsageInfo>> getUsageStatsForRange({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    debugLog.api('UsageStatsService', 'Fetching usage stats for custom range', data: {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'durationHours': endTime.difference(startTime).inHours,
    });
    
    try {
      final stopwatch = Stopwatch()..start();
      final List<dynamic> result = await platform.invokeMethod(
        'getUsageStatsForRange',
        {
          'startTime': startTime.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
        },
      );
      stopwatch.stop();
      
      final apps = result.map((data) => AppUsageInfo.fromMap(data)).toList();
      
      debugLog.success('UsageStatsService', 'Custom range stats fetched', data: {
        'appCount': apps.length,
        'fetchTimeMs': stopwatch.elapsedMilliseconds,
        'rangeHours': endTime.difference(startTime).inHours,
      });
      
      return apps;
    } on PlatformException catch (e) {
      debugLog.error('UsageStatsService', 'Failed to fetch custom range stats', data: {
        'error': e.message,
        'code': e.code,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
      });
      return [];
    }
  }

  /// Get total screen time in milliseconds
  /// 
  /// [mode] - The time window to query (default: today)
  static Future<int> getTotalScreenTime({
    UsageTimeWindow mode = UsageTimeWindow.today,
  }) async {
    final stats = await getUsageStats(mode: mode);
    int total = 0;
    for (var app in stats) {
      total += app.totalTimeInForeground;
    }
    return total;
  }

  /// Get total screen time for a custom range in milliseconds
  static Future<int> getTotalScreenTimeForRange({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final stats = await getUsageStatsForRange(
      startTime: startTime,
      endTime: endTime,
    );
    int total = 0;
    for (var app in stats) {
      total += app.totalTimeInForeground;
    }
    return total;
  }

  /// Get usage stats that match Digital Wellbeing's rolling 24h calculation
  /// This is the recommended method if you want to match Digital Wellbeing numbers
  static Future<List<AppUsageInfo>> getDigitalWellbeingStats() async {
    return getUsageStats(mode: UsageTimeWindow.rolling24h);
  }
}

/// Data model for app usage information
class AppUsageInfo {
  final String packageName;
  final String appName;
  final int totalTimeInForeground;
  final int lastTimeUsed;
  final int hours;
  final int minutes;
  final int seconds;
  final String formattedTime;
  final bool isSystemApp;

  AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.totalTimeInForeground,
    required this.lastTimeUsed,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.formattedTime,
    required this.isSystemApp,
  });

  factory AppUsageInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppUsageInfo(
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? 'Unknown',
      totalTimeInForeground: (map['totalTimeInForeground'] as num?)?.toInt() ?? 0,
      lastTimeUsed: (map['lastTimeUsed'] as num?)?.toInt() ?? 0,
      hours: (map['hours'] as num?)?.toInt() ?? 0,
      minutes: (map['minutes'] as num?)?.toInt() ?? 0,
      seconds: (map['seconds'] as num?)?.toInt() ?? 0,
      formattedTime: map['formattedTime']?.toString() ?? '0s',
      isSystemApp: map['isSystemApp'] as bool? ?? false,
    );
  }

  /// Get usage percentage relative to total time
  double getUsagePercentage(int totalUsageTime) {
    if (totalUsageTime == 0) return 0.0;
    return (totalTimeInForeground / totalUsageTime * 100).clamp(0.0, 100.0);
  }

  /// Check if this is a social media app
  bool isSocialMediaApp() {
    final socialMediaKeywords = [
      'facebook',
      'instagram',
      'whatsapp',
      'telegram',
      'snapchat',
      'tiktok',
      'twitter',
      'linkedin',
      'messenger',
      'reddit',
      'discord',
      'pinterest',
      'youtube',
    ];
    final lowerPackage = packageName.toLowerCase();
    final lowerName = appName.toLowerCase();
    return socialMediaKeywords.any(
      (keyword) => lowerPackage.contains(keyword) || lowerName.contains(keyword),
    );
  }

  /// Check if this is a productivity app
  bool isProductivityApp() {
    final productivityKeywords = [
      'calendar',
      'mail',
      'email',
      'office',
      'docs',
      'sheets',
      'drive',
      'notes',
      'notion',
      'slack',
      'teams',
      'zoom',
      'meet',
    ];
    final lowerPackage = packageName.toLowerCase();
    final lowerName = appName.toLowerCase();
    return productivityKeywords.any(
      (keyword) => lowerPackage.contains(keyword) || lowerName.contains(keyword),
    );
  }

  /// Check if this is a gaming app
  bool isGamingApp() {
    final gamingKeywords = [
      'game',
      'games',
      'play',
      'candy',
      'clash',
      'pubg',
      'minecraft',
      'roblox',
      'fortnite',
    ];
    final lowerPackage = packageName.toLowerCase();
    final lowerName = appName.toLowerCase();
    return gamingKeywords.any(
      (keyword) => lowerPackage.contains(keyword) || lowerName.contains(keyword),
    );
  }
}

