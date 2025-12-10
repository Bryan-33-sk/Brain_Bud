import 'dart:async';

/// Log entry types for categorizing debug logs
enum LogType {
  info,
  success,
  warning,
  error,
  data,
  api,
}

/// A single log entry
class DebugLogEntry {
  final DateTime timestamp;
  final LogType type;
  final String title;
  final String message;
  final Map<String, dynamic>? data;

  DebugLogEntry({
    required this.timestamp,
    required this.type,
    required this.title,
    required this.message,
    this.data,
  });

  String get typeIcon {
    switch (type) {
      case LogType.info:
        return 'ℹ️';
      case LogType.success:
        return '✅';
      case LogType.warning:
        return '⚠️';
      case LogType.error:
        return '❌';
      case LogType.data:
        return '📊';
      case LogType.api:
        return '🔌';
    }
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// Singleton service to capture and store debug logs
class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<DebugLogEntry> _logs = [];
  final _logController = StreamController<List<DebugLogEntry>>.broadcast();

  /// Stream of log entries for reactive UI updates
  Stream<List<DebugLogEntry>> get logStream => _logController.stream;

  /// Get all logs (newest first)
  List<DebugLogEntry> get logs => List.unmodifiable(_logs.reversed.toList());

  /// Maximum number of logs to keep
  static const int maxLogs = 500;

  /// Add a log entry
  void log(LogType type, String title, String message, {Map<String, dynamic>? data}) {
    final entry = DebugLogEntry(
      timestamp: DateTime.now(),
      type: type,
      title: title,
      message: message,
      data: data,
    );

    _logs.add(entry);

    // Trim old logs if exceeds max
    if (_logs.length > maxLogs) {
      _logs.removeRange(0, _logs.length - maxLogs);
    }

    _logController.add(logs);
  }

  /// Convenience methods for different log types
  void info(String title, String message, {Map<String, dynamic>? data}) {
    log(LogType.info, title, message, data: data);
  }

  void success(String title, String message, {Map<String, dynamic>? data}) {
    log(LogType.success, title, message, data: data);
  }

  void warning(String title, String message, {Map<String, dynamic>? data}) {
    log(LogType.warning, title, message, data: data);
  }

  void error(String title, String message, {Map<String, dynamic>? data}) {
    log(LogType.error, title, message, data: data);
  }

  void data(String title, String message, {Map<String, dynamic>? data}) {
    log(LogType.data, title, message, data: data);
  }

  void api(String title, String message, {Map<String, dynamic>? data}) {
    log(LogType.api, title, message, data: data);
  }

  /// Clear all logs
  void clear() {
    _logs.clear();
    _logController.add(logs);
  }

  /// Export logs as a formatted string
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== Brain Bud Debug Logs ===');
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('');

    for (final entry in _logs) {
      buffer.writeln('${entry.formattedTime} [${entry.type.name.toUpperCase()}] ${entry.title}');
      buffer.writeln('  ${entry.message}');
      if (entry.data != null) {
        entry.data!.forEach((key, value) {
          buffer.writeln('    $key: $value');
        });
      }
      buffer.writeln('');
    }

    return buffer.toString();
  }

  void dispose() {
    _logController.close();
  }
}

/// Global instance for easy access
final debugLog = DebugLogService();

