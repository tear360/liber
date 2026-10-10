import 'package:intl/intl.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

/// In-memory journal of what the SDK and the app did, kept long enough to be
/// read on the device itself.
///
/// The Matrix SDK swallows most failures into its own logger, which the user
/// never sees — so a locked message or a failed send used to be undiagnosable
/// without a debugger. Hooking [Logs.onLog] here (once, at bootstrap) keeps
/// the last [maxLines] events around, and « Sécurité → Journal » shows them
/// so the cause of a problem can be read — and copied — from the phone.
class Diagnostics {
  Diagnostics._();

  static final Diagnostics instance = Diagnostics._();

  /// Last events kept in memory. Nothing leaves the device.
  static const int maxLines = 300;

  final List<String> _lines = <String>[];
  bool _attached = false;

  /// Formatter built once: constructing a [DateFormat] on every log line is
  /// measurable during sync chatter.
  static final DateFormat _stampFormat = DateFormat.Hms();

  /// True once the SDK's log stream has been captured at least once.
  bool get attached => _attached;

  /// Number of events currently held (for tests and the UI).
  int get length => _lines.length;

  /// Hooks the SDK logger. Calling it twice is a no-op; the previous callback
  /// (there is none in this app) would be replaced.
  void attachSdkLogs() {
    if (_attached) return;
    _attached = true;
    Logs().onLog = (event) {
      // Debug and verbose drown the buffer in sync chatter; keep them only
      // when they are about the parts this app is judged on.
      final interesting = event.level.index <= Level.info.index ||
          _cryptoKeyword.hasMatch(event.title);
      if (!interesting) return;
      final detail = event.exception?.toString();
      add(
        'sdk:${event.level.name} ${event.title}'
        '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
      );
    };
  }

  /// Debug lines about crypto are the ones that explain a locked message.
  static final _cryptoKeyword = RegExp(
    r'decrypt|olm|megolm|session|key|verif|backup|encrypt',
    caseSensitive: false,
  );

  /// Appends one line with a wall-clock stamp. Oldest lines are dropped.
  ///
  /// Never throws: it is also the sink for uncaught errors, so a failure here
  /// (the French date data not loaded yet at very early startup) must not
  /// take the app down a second time.
  void add(String message) {
    String stamp;
    try {
      stamp = _stampFormat.format(DateTime.now());
    } catch (_) {
      final now = DateTime.now();
      stamp = '${now.hour}:${now.minute}:${now.second}';
    }
    _lines.add('[$stamp] $message');
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  /// The journal, newest last — ready to be shown or copied.
  String snapshot() => _lines.join('\n');

  void clear() => _lines.clear();
}
