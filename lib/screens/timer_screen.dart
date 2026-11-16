import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import 'capture_screen.dart';

/// Countdown for the strip's development time, then opens the camera.
class TimerScreen extends StatefulWidget {
  final MeasureRequest request;
  const TimerScreen({super.key, required this.request});
  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  late final int _total = AppServices.instance.devTimeSeconds;
  late DateTime _end = DateTime.now().add(Duration(seconds: _total));
  Timer? _ticker;
  Duration _left = Duration.zero;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _left = Duration(seconds: _total);
    // Tick often and compute the remaining time from the clock, so the
    // countdown stays accurate even if a frame is late.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    final left = _end.difference(DateTime.now());
    if (left <= Duration.zero && !_done) {
      _done = true;
      _ticker?.cancel();
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      _openCamera();
      return;
    }
    if (mounted) setState(() => _left = left);
  }

  void _openCamera() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CaptureScreen(request: widget.request, timerEnd: _end)));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = (_left.inMilliseconds / 1000).ceil().clamp(0, 9999);
    final frac = _total == 0 ? 0.0 : (_left.inMilliseconds / (_total * 1000)).clamp(0.0, 1.0);
    final cal = widget.request.mode == MeasureMode.calibration;
    return Scaffold(
      appBar: AppBar(
          title: Text(cal
              ? 'Standard ${widget.request.standardConcentration} mg/L'
              : 'Developing')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(value: frac, strokeWidth: 12),
              Center(
                  child: Text('$secs',
                      style: Theme.of(context).textTheme.displayLarge)),
            ]),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Lay the strip pad-up in the card\'s strip slot. '
              'The camera opens automatically when time is up. Photograph straight away; '
              'the pad keeps changing color.',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(
                onPressed: () => setState(() => _end = _end.add(const Duration(seconds: 10))),
                child: const Text('+10 s')),
            const SizedBox(width: 12),
            TextButton(
                onPressed: () {
                  _ticker?.cancel();
                  _done = true;
                  _end = DateTime.now();
                  _openCamera();
                },
                child: const Text('Skip')),
          ]),
        ]),
      ),
    );
  }
}
