import 'dart:async';

typedef TimerCallback = void Function();
typedef TimerCalculation = int Function(int tries);

/// Creates a timer that accepts a `timerCalc` function to perform
/// calculated timeout retries, such as exponential backoff.
///
/// ```dart
/// int calculateRetryDuration(int tries) {
///   return [1000, 5000, 10000][tries - 1] ?? 10000;
/// }
///
/// let reconnectTimer = new RetryTimer(() => this.connect(), calculateRetryDuration)
///
/// reconnectTimer.scheduleTimeout() // fires after 1000
/// reconnectTimer.scheduleTimeout() // fires after 5000
/// reconnectTimer.reset()
/// reconnectTimer.scheduleTimeout() // fires after 1000
/// ```
class RetryTimer {
  final TimerCallback callback;
  final TimerCalculation timerCalc;

  Timer? _timer;
  int _tries = 0;

  RetryTimer(this.callback, this.timerCalc);

  /// Cancels any previous timer and reset tries
  void reset() {
    _tries = 0;
    if (_timer != null) _timer!.cancel();
  }

  /// Cancels any previous scheduleTimeout and schedules callback
  void scheduleTimeout() {
    if (_timer != null) _timer!.cancel();

    _timer = Timer(Duration(milliseconds: timerCalc(_tries + 1)), () {
      _tries = _tries + 1;
      callback();
    });
  }
}
