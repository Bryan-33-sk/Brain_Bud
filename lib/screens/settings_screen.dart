import 'package:flutter/material.dart';
import '../services/app_intervention_service.dart';
import '../services/usage_stats_service.dart';
import 'app_selection_screen.dart';
import 'permission_debug_screen.dart';
import 'permission_onboarding_screen.dart';
import 'debug_log_screen.dart';

/// Settings screen with all configuration options
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _interventionService = AppInterventionService();
  
  bool _interventionsEnabled = true;
  bool _isLoading = true;
  
  // Permission status
  bool _hasUsagePermission = false;
  bool _hasOverlayPermission = false;
  bool _hasAccessibilityPermission = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    final enabled = await _interventionService.areInterventionsEnabled();
    final hasUsage = await UsageStatsService.hasUsagePermission();
    final hasOverlay = await _interventionService.hasOverlayPermission();
    final hasAccessibility = await _interventionService.isAccessibilityServiceRunning();
    
    if (mounted) {
      setState(() {
        _interventionsEnabled = enabled;
        _hasUsagePermission = hasUsage;
        _hasOverlayPermission = hasOverlay;
        _hasAccessibilityPermission = hasAccessibility;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleInterventions(bool value) async {
    await _interventionService.setInterventionsEnabled(value);
    setState(() => _interventionsEnabled = value);
    
    if (value) {
      await _interventionService.startMonitoring();
    } else {
      await _interventionService.stopMonitoring();
    }
  }

  int get _permissionCount {
    int count = 0;
    if (_hasUsagePermission) count++;
    if (_hasOverlayPermission) count++;
    if (_hasAccessibilityPermission) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Interventions Section
                    _buildSectionHeader('INTERVENTIONS'),
                    const SizedBox(height: 12),
                    
                    _buildSettingsTile(
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFF7C3AED),
                      title: 'App Interventions',
                      subtitle: _interventionsEnabled 
                          ? 'Active • Monitoring social media apps'
                          : 'Disabled',
                      trailing: Switch.adaptive(
                        value: _interventionsEnabled,
                        onChanged: _toggleInterventions,
                        activeColor: const Color(0xFF7C3AED),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    _buildSettingsTile(
                      icon: Icons.apps_rounded,
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Monitored Apps',
                      subtitle: 'Choose which apps trigger interventions',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AppSelectionScreen(),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Permissions Section
                    _buildSectionHeader('PERMISSIONS'),
                    const SizedBox(height: 12),
                    
                    _buildSettingsTile(
                      icon: _permissionCount == 3 
                          ? Icons.check_circle 
                          : Icons.warning_rounded,
                      iconColor: _permissionCount == 3 
                          ? Colors.green 
                          : Colors.orange,
                      title: 'Permission Status',
                      subtitle: '$_permissionCount of 3 permissions granted',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PermissionDebugScreen(),
                          ),
                        ).then((_) => _loadSettings());
                      },
                    ),
                    
                    const SizedBox(height: 8),
                    
                    _buildSettingsTile(
                      icon: Icons.play_circle_outline,
                      iconColor: const Color(0xFF10B981),
                      title: 'Setup Guide',
                      subtitle: 'Step-by-step permission walkthrough',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PermissionOnboardingScreen(
                              onComplete: () {
                                _interventionService.startMonitoring();
                                _loadSettings();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Developer Section
                    _buildSectionHeader('DEVELOPER'),
                    const SizedBox(height: 12),
                    
                    _buildSettingsTile(
                      icon: Icons.bug_report_outlined,
                      iconColor: Colors.grey,
                      title: 'Debug Logs',
                      subtitle: 'View app logs and diagnostics',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DebugLogScreen(),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 8),
                    
                    _buildSettingsTile(
                      icon: Icons.info_outline,
                      iconColor: Colors.grey,
                      title: 'About',
                      subtitle: 'Version 1.0.0',
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Brain Bud',
                          applicationVersion: '1.0.0',
                          applicationLegalese: '© 2024 Brain Bud',
                          children: [
                            const SizedBox(height: 16),
                            const Text(
                              'A mindful screen time companion that helps you build healthier digital habits.',
                            ),
                          ],
                        );
                      },
                    ),
                    
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ),
        trailing: trailing ?? (onTap != null 
            ? Icon(
                Icons.chevron_right,
                color: Colors.white.withOpacity(0.3),
              )
            : null),
        onTap: onTap,
      ),
    );
  }
}

