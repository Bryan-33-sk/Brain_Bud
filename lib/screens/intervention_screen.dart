import 'package:flutter/material.dart';
import '../services/app_intervention_service.dart';

/// Intervention screen shown when user tries to open a social media app
class InterventionScreen extends StatefulWidget {
  final String packageName;
  final String appName;
  final VoidCallback onCancel;
  final VoidCallback onContinue;

  const InterventionScreen({
    super.key,
    required this.packageName,
    required this.appName,
    required this.onCancel,
    required this.onContinue,
  });

  @override
  State<InterventionScreen> createState() => _InterventionScreenState();
}

class _InterventionScreenState extends State<InterventionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;

  int _attemptCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
    _loadData();
  }

  Future<void> _loadData() async {
    final interventionService = AppInterventionService();
    _attemptCount = await interventionService.getTotalAttemptsLast24h(widget.packageName);

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    widget.onCancel();
  }

  void _continue() {
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Column(
                  children: [
                    // Top text with highlighted "think"
                    Padding(
                      padding: const EdgeInsets.only(top: 60, left: 24, right: 24),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                          children: [
                            TextSpan(text: "...your brain gets a\nchance to "),
                            TextSpan(
                              text: "think twice",
                              style: TextStyle(
                                color: Color(0xFF7C3AED),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ":"),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Large centered number
                    Text(
                      '$_attemptCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w300,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Attempts text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        'attempts to open ${widget.appName} within the\nlast 24 hours.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Purple button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _cancel,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'I don\'t want to open ${widget.appName}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Continue link
                    TextButton(
                      onPressed: _continue,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: Text(
                        'Continue on ${widget.appName}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
        ),
      ),
    );
  }
}
