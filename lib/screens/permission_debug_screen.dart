import 'package:flutter/material.dart';
import '../services/usage_stats_service.dart';
import '../services/app_intervention_service.dart';

/// Debug screen to check all permissions and their status
class PermissionDebugScreen extends StatefulWidget {
  const PermissionDebugScreen({super.key});

  @override
  State<PermissionDebugScreen> createState() => _PermissionDebugScreenState();
}

class _PermissionDebugScreenState extends State<PermissionDebugScreen> {
  final _interventionService = AppInterventionService();
  
  bool _isLoading = true;
  Map<String, dynamic> _permissionStatus = {};
  List<AppUsageInfo> _usageStats = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check all permissions
      final hasUsage = await UsageStatsService.hasUsagePermission();
      final hasOverlay = await _interventionService.hasOverlayPermission();
      final hasAccessibility = await _interventionService.isAccessibilityServiceRunning();
      final hasBattery = await _interventionService.isBatteryOptimizationDisabled();
      
      // Try to get usage stats
      List<AppUsageInfo> stats = [];
      String? usageError;
      try {
        stats = await UsageStatsService.getUsageStats(mode: UsageTimeWindow.today);
      } catch (e) {
        usageError = e.toString();
      }

      setState(() {
        _permissionStatus = {
          'Usage Access': {
            'granted': hasUsage,
            'description': 'Required to read screen time data',
          },
          'Overlay': {
            'granted': hasOverlay,
            'description': 'Required to show intervention screen',
          },
          'Accessibility': {
            'granted': hasAccessibility,
            'description': 'Required for instant app detection',
          },
          'Battery Optimization': {
            'granted': hasBattery,
            'description': 'Prevents service from being killed',
          },
        };
        _usageStats = stats;
        if (usageError != null) {
          _error = 'Usage Stats Error: $usageError';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text('Permission Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Permission Status
                  const Text(
                    'PERMISSIONS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  ..._permissionStatus.entries.map((entry) {
                    final name = entry.key;
                    final data = entry.value as Map<String, dynamic>;
                    final granted = data['granted'] as bool;
                    final description = data['description'] as String;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: granted 
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: granted
                              ? Colors.green.withOpacity(0.3)
                              : Colors.red.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            granted ? Icons.check_circle : Icons.cancel,
                            color: granted ? Colors.green : Colors.red,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  description,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            granted ? 'GRANTED' : 'DENIED',
                            style: TextStyle(
                              color: granted ? Colors.green : Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  
                  const SizedBox(height: 24),
                  
                  // Quick Actions
                  const Text(
                    'QUICK ACTIONS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildActionButton(
                        'Open Usage Settings',
                        () => UsageStatsService.openUsageSettings(),
                      ),
                      _buildActionButton(
                        'Request Overlay',
                        () => _interventionService.requestOverlayPermission(),
                      ),
                      _buildActionButton(
                        'Open Accessibility',
                        () => _interventionService.requestAccessibilityPermission(),
                      ),
                      _buildActionButton(
                        'Battery Settings',
                        () => _interventionService.requestBatteryOptimizationExemption(),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Error display
                  if (_error != null) ...[
                    const Text(
                      'ERRORS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Usage Stats
                  const Text(
                    'USAGE STATS TEST',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  if (_usageStats.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning, color: Colors.orange),
                              SizedBox(width: 12),
                              Text(
                                'No Usage Data',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This could mean:\n'
                            '• Usage Access permission not granted\n'
                            '• No apps have been used today\n'
                            '• Device just started collecting data',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 12),
                              Text(
                                '${_usageStats.length} apps tracked',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Top 5 Apps Today:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._usageStats.take(5).map((app) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    app.appName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  app.formattedTime,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

