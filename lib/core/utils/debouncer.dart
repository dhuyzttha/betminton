import 'dart:async';
import 'package:flutter/foundation.dart';

/// Ultra-smooth Throttler & Debouncer for 60Hz/120Hz high refresh rate mobile screens.
/// Guarantees that frequent slider events (seeking video, threshold adjustments)
/// do not flood the video decoder isolate or cause UI frame drops.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 150)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

class Throttler {
  final Duration interval;
  Timer? _timer;
  bool _ready = true;
  VoidCallback? _trailingAction;

  Throttler({this.interval = const Duration(milliseconds: 32)}); // ~30-60 updates/sec max

  void run(VoidCallback action) {
    if (_ready) {
      _ready = false;
      action();
      _timer = Timer(interval, () {
        _ready = true;
        if (_trailingAction != null) {
          final trailing = _trailingAction;
          _trailingAction = null;
          run(trailing!);
        }
      });
    } else {
      _trailingAction = action;
    }
  }

  void dispose() {
    _timer?.cancel();
    _trailingAction = null;
  }
}
