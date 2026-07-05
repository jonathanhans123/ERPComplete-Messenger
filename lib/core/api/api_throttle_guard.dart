/// Tracks API rate-limit (429) backoff so the app stops hammering the server.
class ApiThrottleGuard {
  ApiThrottleGuard._();
  static final instance = ApiThrottleGuard._();

  DateTime? _blockedUntil;
  int _strikeCount = 0;

  bool get isBlocked =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  Duration? get retryIn {
    if (!isBlocked || _blockedUntil == null) return null;
    final diff = _blockedUntil!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  void register429() {
    _strikeCount = (_strikeCount + 1).clamp(1, 6);
    final seconds = (30 * _strikeCount).clamp(30, 300);
    _blockedUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  void registerSuccess() {
    if (!isBlocked) {
      _strikeCount = 0;
    }
  }

  void clear() {
    _blockedUntil = null;
    _strikeCount = 0;
  }

  String get userMessage {
    final wait = retryIn;
    if (wait == null) return 'Too many requests. Please wait and try again.';
    final secs = wait.inSeconds;
    if (secs < 60) return 'Too many requests. Wait about $secs seconds.';
    return 'Too many requests. Wait about ${(secs / 60).ceil()} minutes.';
  }
}
