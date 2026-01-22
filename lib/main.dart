import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/usage_stats_service.dart';
import 'services/debug_log_service.dart';
import 'services/notification_service.dart';
import 'services/usage_monitor_service.dart';
import 'services/achievement_service.dart';
import 'screens/debug_log_screen.dart';
import 'screens/category_breakdown_screen.dart';
import 'screens/achievements_screen.dart';
import 'services/app_intervention_service.dart';
import 'widgets/intervention_overlay.dart';
import 'screens/permission_debug_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Initialize background monitoring
  final monitorService = UsageMonitorService();
  await monitorService.initialize();

  // Initialize achievements
  final achievementService = AchievementService();
  await achievementService.initialize();

  // Initialize intervention service
  final interventionService = AppInterventionService();
  await interventionService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Global navigator key for accessing context from services
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Set context provider for intervention service
    final interventionService = AppInterventionService();
    interventionService.setContextProvider(() => navigatorKey.currentContext);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Brain Bud',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ScreenTimePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Brain Bud mood based on social media usage
enum BrainBudMood {
  happy, // Low social media usage (< 30 min)
  neutral, // Moderate usage (30 min - 2 hours)
  sad, // High usage (> 2 hours)
}

/// The Brain Bud character widget with expressive face
class BrainBudCharacter extends StatefulWidget {
  final BrainBudMood mood;
  final double size;

  const BrainBudCharacter({
    super.key,
    required this.mood,
    this.size = 200,
  });

  @override
  State<BrainBudCharacter> createState() => _BrainBudCharacterState();
}

class _BrainBudCharacterState extends State<BrainBudCharacter>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -_bounceAnimation.value),
          child: child,
        );
      },
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: BrainBudPainter(mood: widget.mood),
      ),
    );
  }
}

/// Custom painter for the Brain Bud character
class BrainBudPainter extends CustomPainter {
  final BrainBudMood mood;

  BrainBudPainter({required this.mood});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Get colors based on mood
    final (mainColor, accentColor) = _getMoodColors();

    // Draw shadow
    final shadowPaint = Paint()
      ..color = mainColor.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center + const Offset(0, 10), radius, shadowPaint);

    // Draw main body (brain-like blob)
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor,
          mainColor,
        ],
        stops: const [0.3, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    // Draw brain-like shape
    _drawBrainShape(canvas, center, radius, bodyPaint);

    // Draw face
    _drawFace(canvas, center, radius);

    // Draw brain wrinkles/details
    _drawBrainDetails(canvas, center, radius, mainColor);
  }

  (Color, Color) _getMoodColors() {
    switch (mood) {
      case BrainBudMood.happy:
        return (const Color(0xFF10B981), const Color(0xFF6EE7B7)); // Green
      case BrainBudMood.neutral:
        return (
          const Color(0xFFF59E0B),
          const Color(0xFFFCD34D)
        ); // Yellow/Amber
      case BrainBudMood.sad:
        return (const Color(0xFFEF4444), const Color(0xFFFCA5A5)); // Red
    }
  }

  void _drawBrainShape(
      Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();

    // Create a brain-like blob shape
    for (int i = 0; i <= 360; i += 5) {
      final angle = i * math.pi / 180;
      // Add some waviness to make it look like a brain
      final waveOffset = math.sin(angle * 6) * (radius * 0.08);
      final r = radius + waveOffset;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    // Draw outline
    final outlinePaint = Paint()
      ..color = _getMoodColors().$1.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, outlinePaint);
  }

  void _drawFace(Canvas canvas, Offset center, double radius) {
    final eyeRadius = radius * 0.12;
    final eyeOffsetX = radius * 0.28;
    final eyeOffsetY = radius * 0.1;

    // White of eyes
    final eyeWhitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(center.dx - eyeOffsetX, center.dy - eyeOffsetY),
      eyeRadius * 1.3,
      eyeWhitePaint,
    );
    canvas.drawCircle(
      Offset(center.dx + eyeOffsetX, center.dy - eyeOffsetY),
      eyeRadius * 1.3,
      eyeWhitePaint,
    );

    // Pupils - position based on mood
    final pupilPaint = Paint()..color = const Color(0xFF1F2937);
    final pupilOffset = mood == BrainBudMood.sad
        ? const Offset(0, 3) // Look down when sad
        : const Offset(0, 0);

    canvas.drawCircle(
      Offset(center.dx - eyeOffsetX, center.dy - eyeOffsetY) + pupilOffset,
      eyeRadius * 0.7,
      pupilPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + eyeOffsetX, center.dy - eyeOffsetY) + pupilOffset,
      eyeRadius * 0.7,
      pupilPaint,
    );

    // Eye shine
    final shinePaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(center.dx - eyeOffsetX - 2, center.dy - eyeOffsetY - 3) +
          pupilOffset,
      eyeRadius * 0.25,
      shinePaint,
    );
    canvas.drawCircle(
      Offset(center.dx + eyeOffsetX - 2, center.dy - eyeOffsetY - 3) +
          pupilOffset,
      eyeRadius * 0.25,
      shinePaint,
    );

    // Eyebrows based on mood
    _drawEyebrows(canvas, center, radius, eyeOffsetX, eyeOffsetY);

    // Mouth based on mood
    _drawMouth(canvas, center, radius);

    // Blush for happy mood
    if (mood == BrainBudMood.happy) {
      final blushPaint = Paint()
        ..color = const Color(0xFFFFB6C1).withOpacity(0.5);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx - radius * 0.45, center.dy + radius * 0.1),
          width: radius * 0.2,
          height: radius * 0.12,
        ),
        blushPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + radius * 0.45, center.dy + radius * 0.1),
          width: radius * 0.2,
          height: radius * 0.12,
        ),
        blushPaint,
      );
    }
  }

  void _drawEyebrows(Canvas canvas, Offset center, double radius,
      double eyeOffsetX, double eyeOffsetY) {
    final browPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final browY = center.dy - eyeOffsetY - radius * 0.22;

    switch (mood) {
      case BrainBudMood.happy:
        // Raised, curved eyebrows
        final leftBrow = Path()
          ..moveTo(center.dx - eyeOffsetX - radius * 0.12, browY + 2)
          ..quadraticBezierTo(
            center.dx - eyeOffsetX,
            browY - 5,
            center.dx - eyeOffsetX + radius * 0.12,
            browY + 2,
          );
        final rightBrow = Path()
          ..moveTo(center.dx + eyeOffsetX - radius * 0.12, browY + 2)
          ..quadraticBezierTo(
            center.dx + eyeOffsetX,
            browY - 5,
            center.dx + eyeOffsetX + radius * 0.12,
            browY + 2,
          );
        canvas.drawPath(leftBrow, browPaint);
        canvas.drawPath(rightBrow, browPaint);
        break;

      case BrainBudMood.neutral:
        // Straight eyebrows
        canvas.drawLine(
          Offset(center.dx - eyeOffsetX - radius * 0.1, browY),
          Offset(center.dx - eyeOffsetX + radius * 0.1, browY),
          browPaint,
        );
        canvas.drawLine(
          Offset(center.dx + eyeOffsetX - radius * 0.1, browY),
          Offset(center.dx + eyeOffsetX + radius * 0.1, browY),
          browPaint,
        );
        break;

      case BrainBudMood.sad:
        // Worried, angled eyebrows
        canvas.drawLine(
          Offset(center.dx - eyeOffsetX - radius * 0.1, browY - 3),
          Offset(center.dx - eyeOffsetX + radius * 0.1, browY + 5),
          browPaint,
        );
        canvas.drawLine(
          Offset(center.dx + eyeOffsetX + radius * 0.1, browY - 3),
          Offset(center.dx + eyeOffsetX - radius * 0.1, browY + 5),
          browPaint,
        );
        break;
    }
  }

  void _drawMouth(Canvas canvas, Offset center, double radius) {
    final mouthPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final mouthY = center.dy + radius * 0.35;
    final mouthWidth = radius * 0.35;

    switch (mood) {
      case BrainBudMood.happy:
        // Big smile
        final smilePath = Path()
          ..moveTo(center.dx - mouthWidth, mouthY - 5)
          ..quadraticBezierTo(
            center.dx,
            mouthY + radius * 0.2,
            center.dx + mouthWidth,
            mouthY - 5,
          );
        canvas.drawPath(smilePath, mouthPaint);
        break;

      case BrainBudMood.neutral:
        // Straight line
        canvas.drawLine(
          Offset(center.dx - mouthWidth * 0.6, mouthY),
          Offset(center.dx + mouthWidth * 0.6, mouthY),
          mouthPaint,
        );
        break;

      case BrainBudMood.sad:
        // Frown
        final frownPath = Path()
          ..moveTo(center.dx - mouthWidth * 0.8, mouthY + 5)
          ..quadraticBezierTo(
            center.dx,
            mouthY - radius * 0.12,
            center.dx + mouthWidth * 0.8,
            mouthY + 5,
          );
        canvas.drawPath(frownPath, mouthPaint);
        break;
    }
  }

  void _drawBrainDetails(
      Canvas canvas, Offset center, double radius, Color color) {
    final detailPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw some wavy lines to look like brain folds
    for (int i = 0; i < 3; i++) {
      final startAngle = (i * 120 + 30) * math.pi / 180;
      final path = Path();

      for (int j = 0; j <= 30; j++) {
        final t = j / 30;
        final angle = startAngle + t * 0.8;
        final r = radius * (0.5 + t * 0.3);
        final wave = math.sin(t * math.pi * 3) * 5;
        final x = center.dx + (r + wave) * math.cos(angle);
        final y = center.dy + (r + wave) * math.sin(angle);

        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, detailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BrainBudPainter oldDelegate) {
    return oldDelegate.mood != mood;
  }
}

class ScreenTimePage extends StatefulWidget {
  const ScreenTimePage({super.key});

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage> {
  List<AppUsageInfo> _usageStats = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String _errorMessage = '';
  bool _debugMode = false;
  int _debugSocialTimeOffset = 0; // Offset in milliseconds
  bool _interventionsEnabled = true;

  // Social media time thresholds (in milliseconds)
  static const int _happyThreshold = 30 * 60 * 1000; // 30 minutes
  static const int _neutralThreshold = 2 * 60 * 60 * 1000; // 2 hours

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoadData();
    _loadInterventionSettings();
    _setupInterventionMonitoring();
  }

  Future<void> _loadInterventionSettings() async {
    final interventionService = AppInterventionService();
    final enabled = await interventionService.areInterventionsEnabled();
    setState(() {
      _interventionsEnabled = enabled;
    });

    // If interventions are enabled, ensure overlay permission is granted
    // (required for native Android overlay to appear on top of other apps)
    if (enabled) {
      final hasOverlay = await interventionService.hasOverlayPermission();
      if (!hasOverlay && mounted) {
        // Trigger the system permission screen
        await interventionService.requestOverlayPermission();
      }
    }

    // Start or stop monitoring based on settings
    if (enabled) {
      await interventionService.startMonitoring();
    } else {
      await interventionService.stopMonitoring();
    }
  }

  void _setupInterventionMonitoring() {
    // Note: Intervention overlay is now automatically triggered via the unified
    // _handleAppLaunch() method in AppInterventionService, which piggybacks on
    // the notification system. The callback is kept for backward compatibility
    // and potential future use cases.
    final interventionService = AppInterventionService();

    // Set callback (overlay is now handled automatically in _handleAppLaunch)
    interventionService.setAppLaunchCallback((packageName, appName) {
      // Overlay is automatically shown via _handleAppLaunch()
      // This callback can be used for other purposes if needed
      debugLog.info('InterventionService', 'App launch callback: $packageName');
    });
  }

  Future<void> _checkPermissionAndLoadData() async {
    debugLog.info(
        'Load Data', 'Starting to check permission and load usage stats');

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      debugLog.api('Permission Check', 'Checking usage stats permission...');
      final hasPermission = await UsageStatsService.hasUsagePermission();
      debugLog.info('Permission Result', 'Has permission: $hasPermission');

      if (hasPermission) {
        debugLog.api(
            'Fetch Stats', 'Fetching usage stats from native platform...');
        final startTime = DateTime.now();
        final stats = await UsageStatsService.getUsageStats();
        final duration = DateTime.now().difference(startTime).inMilliseconds;

        debugLog.success(
            'Stats Loaded', 'Loaded ${stats.length} apps in ${duration}ms',
            data: {
              'appCount': stats.length,
              'loadTimeMs': duration,
              'mode': 'today (midnight to now)',
            });

        // Log top 5 apps
        if (stats.isNotEmpty) {
          final topApps = stats
              .take(5)
              .map((a) => '${a.appName}: ${a.formattedTime}')
              .join(', ');
          debugLog.data('Top 5 Apps', topApps);
        }

        // Calculate totals for logging
        final totalTimeMs =
            stats.fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);
        final hours = totalTimeMs ~/ (1000 * 60 * 60);
        final minutes = (totalTimeMs % (1000 * 60 * 60)) ~/ (1000 * 60);
        debugLog.data('Total Screen Time', '${hours}h ${minutes}m', data: {
          'totalMs': totalTimeMs,
          'hours': hours,
          'minutes': minutes,
          'userApps': stats.where((a) => !a.isSystemApp).length,
          'systemApps': stats.where((a) => a.isSystemApp).length,
        });

        setState(() {
          _hasPermission = true;
          _usageStats = stats;
          _isLoading = false;
        });

        // Check for mood changes and send notification if needed
        _checkMoodChange(stats);

        // Check achievements
        final achievementService = AchievementService();
        await achievementService.checkAchievements(stats);
      } else {
        debugLog.warning(
            'No Permission', 'Usage access permission not granted');
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugLog.error('Load Error', 'Failed to load usage stats: $e', data: {
        'error': e.toString(),
        'stackTrace': stackTrace.toString().split('\n').take(5).join('\n'),
      });
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    await UsageStatsService.openUsageSettings();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Usage Access'),
        content: const Text(
          'Please find "Brain Bud" in the list and enable the toggle to grant usage access permission. Then return to the app.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Future.delayed(const Duration(seconds: 1), () {
                _checkPermissionAndLoadData();
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<AppUsageInfo> get _filteredStats {
    return _usageStats.where((app) => !app.isSystemApp).toList();
  }

  int _getTotalUsageTime() {
    return _filteredStats.fold(
        0, (sum, app) => sum + app.totalTimeInForeground);
  }

  int _getSocialMediaTime() {
    final realTime = _filteredStats
        .where((app) => app.isSocialMediaApp())
        .fold(0, (sum, app) => sum + app.totalTimeInForeground);

    // In debug mode, add the offset (can be negative)
    if (_debugMode) {
      return (realTime + _debugSocialTimeOffset).clamp(0, 24 * 60 * 60 * 1000);
    }
    return realTime;
  }

  BrainBudMood _getMood() {
    final socialTime = _getSocialMediaTime();
    if (socialTime < _happyThreshold) {
      return BrainBudMood.happy;
    } else if (socialTime < _neutralThreshold) {
      return BrainBudMood.neutral;
    } else {
      return BrainBudMood.sad;
    }
  }

  String _getMoodMessage() {
    final mood = _getMood();
    final socialMinutes = _getSocialMediaTime() ~/ (1000 * 60);

    switch (mood) {
      case BrainBudMood.happy:
        if (socialMinutes == 0) {
          return "No social media today! I'm so proud of you! 🌟";
        }
        return "Only ${socialMinutes}m on social media. Great balance! 🎉";
      case BrainBudMood.neutral:
        final hours = socialMinutes ~/ 60;
        final mins = socialMinutes % 60;
        return "${hours}h ${mins}m on social media. Maybe take a break? 🤔";
      case BrainBudMood.sad:
        final hours = socialMinutes ~/ 60;
        final mins = socialMinutes % 60;
        return "${hours}h ${mins}m scrolling... I miss the real you 😢";
    }
  }

  Color _getMoodColor() {
    switch (_getMood()) {
      case BrainBudMood.happy:
        return const Color(0xFF10B981);
      case BrainBudMood.neutral:
        return const Color(0xFFF59E0B);
      case BrainBudMood.sad:
        return const Color(0xFFEF4444);
    }
  }

  String _formatTotalTime(int totalTimeMs) {
    final hours = totalTimeMs ~/ (1000 * 60 * 60);
    final minutes = (totalTimeMs % (1000 * 60 * 60)) ~/ (1000 * 60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Check if mood has changed and send notification
  Future<void> _checkMoodChange(List<AppUsageInfo> stats) async {
    try {
      final socialMediaTime = stats
          .where((app) => app.isSocialMediaApp() && !app.isSystemApp)
          .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

      final socialMinutes = socialMediaTime ~/ (1000 * 60);
      final currentMood = _getMood();

      // Get last known mood from storage
      final prefs = await SharedPreferences.getInstance();
      final lastMoodStr = prefs.getString('last_known_mood');

      // Convert enum to string for comparison
      String currentMoodStr = currentMood.toString().split('.').last;

      // Update stored values
      await prefs.setString('last_known_mood', currentMoodStr);
      await prefs.setInt('last_known_social_minutes', socialMinutes);

      // If mood changed, send notification
      if (lastMoodStr != null && lastMoodStr != currentMoodStr) {
        final notificationService = NotificationService();
        await notificationService.initialize();

        String message;
        if (currentMood == BrainBudMood.happy) {
          if (socialMinutes == 0) {
            message = "No social media today! I'm so proud of you! 🌟";
          } else {
            message =
                "Only ${socialMinutes}m on social media. Great balance! 🎉";
          }
        } else if (currentMood == BrainBudMood.neutral) {
          final hours = socialMinutes ~/ 60;
          final mins = socialMinutes % 60;
          message =
              "${hours}h ${mins}m on social media. Maybe take a break? 🤔";
        } else {
          final hours = socialMinutes ~/ 60;
          final mins = socialMinutes % 60;
          message = "${hours}h ${mins}m scrolling... I miss the real you 😢";
        }

        await notificationService.showMoodChangeNotification(
          mood: currentMoodStr,
          message: message,
          socialMediaMinutes: socialMinutes,
        );

        debugLog.success(
            'Mood Change', 'Mood changed: $lastMoodStr → $currentMoodStr');
      }
    } catch (e) {
      debugLog.error('Mood Change', 'Failed to check mood change: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Brain Bud',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.bug_report, color: colorScheme.primary),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DebugLogScreen()),
                );
              },
              tooltip: 'Debug Logs',
            ),
            IconButton(
              icon: Icon(Icons.security, color: colorScheme.primary),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PermissionDebugScreen()),
                );
              },
              tooltip: 'Permission Status',
            ),
          ],
        ),
        leadingWidth: 96,
        actions: [
          // Achievements button
          IconButton(
            icon: Icon(Icons.emoji_events, color: colorScheme.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AchievementsScreen(),
                ),
              );
            },
            tooltip: 'Achievements',
          ),
          // Debug mode toggle
          IconButton(
            icon: Icon(
              _debugMode ? Icons.science : Icons.science_outlined,
              color: _debugMode ? Colors.orange : colorScheme.primary,
            ),
            onPressed: () => setState(() {
              _debugMode = !_debugMode;
              if (!_debugMode) _debugSocialTimeOffset = 0;
            }),
            tooltip: 'Toggle Debug Mode',
          ),
          // Interventions toggle
          IconButton(
            icon: Icon(
              _interventionsEnabled ? Icons.block : Icons.block_outlined,
              color: _interventionsEnabled
                  ? colorScheme.primary
                  : colorScheme.onSurface.withOpacity(0.5),
            ),
            onPressed: () async {
              final interventionService = AppInterventionService();
              final newValue = !_interventionsEnabled;
              await interventionService.setInterventionsEnabled(newValue);

              // Start or stop monitoring based on new value
              if (newValue) {
                await interventionService.startMonitoring();
              } else {
                await interventionService.stopMonitoring();
              }

              setState(() {
                _interventionsEnabled = newValue;
              });
            },
            tooltip: _interventionsEnabled
                ? 'Interventions Enabled'
                : 'Interventions Disabled',
          ),
          // Test intervention button (for testing)
          if (_debugMode)
            IconButton(
              icon: Icon(Icons.play_arrow, color: colorScheme.primary),
              onPressed: () async {
                // Test intervention screen
                final interventionService = AppInterventionService();
                await interventionService
                    .incrementLaunchAttempt('com.instagram.android');
                if (mounted) {
                  await InterventionOverlay.showIntervention(
                    context,
                    'com.instagram.android',
                    'Instagram',
                  );
                }
              },
              tooltip: 'Test Intervention',
            ),
          if (_hasPermission)
            IconButton(
              icon: Icon(Icons.refresh, color: colorScheme.primary),
              onPressed: _isLoading ? null : _checkPermissionAndLoadData,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading usage statistics...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionRequest();
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorState();
    }

    return _buildMainContent();
  }

  Widget _buildPermissionRequest() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.timer_outlined,
                size: 60,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Usage Access Required',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To show app usage statistics, Brain Bud needs usage access permission. This allows us to display how long you\'ve used your apps.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurface.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.settings),
              label: const Text(
                'Grant Permission',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Find Brain Bud in the list and enable access',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Error Loading Data',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, color: colorScheme.onSurface.withOpacity(0.7)),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _checkPermissionAndLoadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final totalUsageTime = _getTotalUsageTime();
    final stats = _filteredStats;
    final mood = _getMood();

    // Count categories
    final socialCount = stats.where((app) => app.isSocialMediaApp()).length;
    final productivityCount =
        stats.where((app) => app.isProductivityApp()).length;
    final gamingCount = stats.where((app) => app.isGamingApp()).length;

    return RefreshIndicator(
      onRefresh: _checkPermissionAndLoadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Brain Bud Character Section (moved to top)
            const SizedBox(height: 20),

            // Character with glow effect based on mood
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _getMoodColor().withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: BrainBudCharacter(
                mood: mood,
                size: 220,
              ),
            ),

            const SizedBox(height: 24),

            // Mood message
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: _getMoodColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getMoodColor().withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Text(
                  _getMoodMessage(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Debug Controls (if enabled)
            _buildDebugControls(),

            // Summary Card - Tappable to show category breakdown
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CategoryBreakdownScreen(
                      usageStats: _usageStats,
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.access_time_filled,
                          size: 20,
                          color: colorScheme.onPrimary.withOpacity(0.8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Total Screen Time Today',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onPrimary.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colorScheme.onPrimary.withOpacity(0.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatTotalTime(totalUsageTime),
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(
                            'Apps', stats.length.toString(), Icons.apps),
                        _buildSummaryItem(
                            'Social', socialCount.toString(), Icons.people),
                        _buildSummaryItem('Productivity',
                            productivityCount.toString(), Icons.work),
                        _buildSummaryItem(
                            'Games', gamingCount.toString(), Icons.games),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Hint text
                    Text(
                      'Tap for detailed breakdown',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimary.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Social media time indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Social Media Time',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Text(
                        _formatTotalTime(_getSocialMediaTime()),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _getMoodColor(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (_getSocialMediaTime() / _neutralThreshold)
                          .clamp(0.0, 1.0),
                      backgroundColor: colorScheme.outline.withOpacity(0.1),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_getMoodColor()),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0m',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        '30m',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        '2h',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.onPrimary.withOpacity(0.8), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onPrimary.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildDebugControls() {
    if (!_debugMode) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final offsetMinutes = _debugSocialTimeOffset ~/ (1000 * 60);
    final realTime = _filteredStats
        .where((app) => app.isSocialMediaApp())
        .fold(0, (sum, app) => sum + app.totalTimeInForeground);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bug_report, color: Colors.orange, size: 16),
              SizedBox(width: 4),
              Text(
                'DEBUG MODE',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Real: ${_formatTotalTime(realTime)} | Offset: ${offsetMinutes >= 0 ? "+" : ""}${offsetMinutes}m',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // -30 min
              _debugButton(
                  '-30m',
                  () =>
                      setState(() => _debugSocialTimeOffset -= 30 * 60 * 1000)),
              const SizedBox(width: 8),
              // -5 min
              _debugButton(
                  '-5m',
                  () =>
                      setState(() => _debugSocialTimeOffset -= 5 * 60 * 1000)),
              const SizedBox(width: 8),
              // Reset
              _debugButton(
                  'Reset', () => setState(() => _debugSocialTimeOffset = 0),
                  isReset: true),
              const SizedBox(width: 8),
              // +5 min
              _debugButton(
                  '+5m',
                  () =>
                      setState(() => _debugSocialTimeOffset += 5 * 60 * 1000)),
              const SizedBox(width: 8),
              // +30 min
              _debugButton(
                  '+30m',
                  () =>
                      setState(() => _debugSocialTimeOffset += 30 * 60 * 1000)),
            ],
          ),
          const SizedBox(height: 8),
          // Quick presets
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _debugPresetButton('Happy\n(<30m)', 15 * 60 * 1000),
              const SizedBox(width: 8),
              _debugPresetButton('Neutral\n(1h)', 60 * 60 * 1000),
              const SizedBox(width: 8),
              _debugPresetButton('Sad\n(3h)', 180 * 60 * 1000),
            ],
          ),
        ],
      ),
    );
  }

  Widget _debugButton(String label, VoidCallback onPressed,
      {bool isReset = false}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: isReset ? Colors.orange : null,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _debugPresetButton(String label, int targetTime) {
    final realTime = _filteredStats
        .where((app) => app.isSocialMediaApp())
        .fold(0, (sum, app) => sum + app.totalTimeInForeground);

    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: () =>
            setState(() => _debugSocialTimeOffset = targetTime - realTime),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: const BorderSide(color: Colors.orange),
        ),
        child: Text(label,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}
