import 'package:flutter/material.dart';
import '../screens/intervention_screen.dart';
import '../services/app_intervention_service.dart';

/// Helper widget to show intervention overlay
class InterventionOverlay {
  static OverlayEntry? _overlayEntry;
  static bool _isShowing = false;

  /// Show intervention screen for a social media app
  /// Note: This is now called directly from AppInterventionService._handleAppLaunch()
  /// which already checks if it's a social media app and if interventions are enabled
  static Future<void> showIntervention(
    BuildContext context,
    String packageName,
    String appName,
  ) async {
    if (_isShowing) return;

    // Note: Social media check and intervention enabled check are done in AppInterventionService
    // This method just displays the overlay

    _isShowing = true;

    _overlayEntry = OverlayEntry(
      builder: (context) => InterventionScreen(
        packageName: packageName,
        appName: appName,
        onCancel: () {
          _hideIntervention();
          // User chose not to open the app
        },
        onContinue: () {
          _hideIntervention();
          // User chose to continue - could launch the app here if needed
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void _hideIntervention() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    _isShowing = false;
  }

  /// Check if intervention should be shown and show it
  /// This can be called from various places (notifications, manual triggers, etc.)
  static Future<void> checkAndShowIntervention(
    BuildContext context,
    String packageName,
    String appName,
  ) async {
    final interventionService = AppInterventionService();
    final attempts = await interventionService.getTotalAttemptsLast24h(packageName);
    
    // Show intervention if user has tried opening this app multiple times
    // or if it's their first attempt and they want to be mindful
    if (attempts >= 1) {
      await showIntervention(context, packageName, appName);
    }
  }
}

