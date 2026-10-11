import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_relay_service.dart';
import '../theme.dart';
import '../widgets/mv_widgets.dart';

class ConnectedScreen extends StatefulWidget {
  final AudioRelayService audio;
  const ConnectedScreen({super.key, required this.audio});

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen> {
  bool _connected = true;
  StreamSubscription? _sub;
  bool _muted = false;
  int _secs = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sub = widget.audio.connectionState.listen((state) {
      if (mounted) setState(() => _connected = state);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connected) setState(() => _secs++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    widget.audio.dispose();
    super.dispose();
  }

  void _disconnect() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.audio.setMuted(_muted);
  }

  String get _timerLabel {
    final mm = (_secs ~/ 60).toString().padLeft(2, '0');
    final ss = (_secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final active = _connected && !_muted;
    final (pillLabel, pillColor) = !_connected
        ? ('Reconectando...', AppColors.orange)
        : _muted
            ? ('Silenciado', AppColors.red)
            : ('Conectado', AppColors.green);

    return Scaffold(
      appBar: const MvAppBar(title: 'MotoVox'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Status pill
              Center(
                child: StatusPill(label: pillLabel, color: pillColor),
              ),

              // Hero
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PulseRings(
                              active: active,
                              size: 160,
                              baseOpacity: 0.8,
                              duration: const Duration(milliseconds: 1800),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _muted
                                    ? AppColors.darkCard
                                    : AppColors.orangeDim,
                                border: Border.all(
                                  color: _muted
                                      ? AppColors.border
                                      : AppColors.orange
                                          .withValues(alpha: 0.6),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: HelmetWidget(
                                  size: 68,
                                  animated: active,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AudioBarsWidget(active: active),
                      const SizedBox(height: 12),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          fontSize: 11,
                          color: _muted ? AppColors.red : AppColors.white40,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                        child: Text(
                          !_connected
                              ? 'SEÑAL PERDIDA'
                              : _muted
                                  ? 'MICRÓFONO SILENCIADO'
                                  : 'SIN PUSH-TO-TALK',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Timer
              Center(
                child: Text(
                  _timerLabel,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 5,
                    shadows: [
                      Shadow(
                        color: AppColors.orangeGlow,
                        blurRadius: 40,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              OutlineBtn(
                label: _muted ? 'Activar micrófono' : 'Silenciar',
                danger: _muted,
                onPressed: _toggleMute,
                icon: Icon(
                  _muted ? Icons.mic_off : Icons.mic,
                  size: 18,
                  color: _muted ? AppColors.red : AppColors.orange,
                ),
              ),
              const SizedBox(height: 10),
              PrimaryBtn(
                label: 'Desconectar',
                danger: true,
                onPressed: _disconnect,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
