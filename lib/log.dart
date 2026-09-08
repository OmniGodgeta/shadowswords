import 'dart:collection';

/// A tiny in-memory ring buffer of recent app events, surfaced by the
/// "Report a problem" screen. Nothing is persisted or sent anywhere on its own.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const _max = 250;
  final Queue<String> _lines = Queue<String>();

  void add(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _lines.addLast('$ts  $message');
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
  }

  List<String> get lines => _lines.toList(growable: false);

  String dump() => _lines.join('\n');

  void clear() => _lines.clear();
}

/// Shorthand.
void logEvent(String message) => AppLog.instance.add(message);
