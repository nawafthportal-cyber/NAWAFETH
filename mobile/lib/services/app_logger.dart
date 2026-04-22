import 'package:flutter/foundation.dart';

/// Lightweight centralized logger for runtime diagnostics.
class AppLogger {
  AppLogger._();

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log('INFO', message, error: error, stackTrace: stackTrace);
  }

  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _log('WARN', message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, error: error, stackTrace: stackTrace);
  }

  static void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final suffix = error == null ? '' : ' | $error';
    debugPrint('[$level] $message$suffix');
    if (kDebugMode && stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
