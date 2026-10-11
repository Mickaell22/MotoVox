import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/audio_relay_service.dart';
import '../services/room_discovery_service.dart';
import '../theme.dart';
import '../widgets/mv_widgets.dart';
import 'connected_screen.dart';

class QrScreen extends StatefulWidget {
  final bool isHost;
  const QrScreen({super.key, required this.isHost});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen>
    with SingleTickerProviderStateMixin {
  String? _qrData;
  String? _statusMsg;
  bool _connecting = false;
  bool _scanned = false;
  bool _navigatedToConnected = false;

  AudioRelayService? _audioService;
  final _discovery = RoomDiscoveryService();
  String? _roomId;

  late final AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    if (widget.isHost) _startHost();
  }

  Future<void> _startHost() async {
    try {
      setState(() => _statusMsg = 'Buscando red...');

      final ip = await localIp();
      if (ip == null) {
        setState(() => _statusMsg =
            'Sin red WiFi o hotspot.\nActiva el hotspot e intenta de nuevo.');
        return;
      }

      setState(() => _statusMsg = 'Iniciando micrófono...');
      _audioService = AudioRelayService();
      await _audioService!.init().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout al iniciar micrófono'),
      );

      await _audioService!.startHost();
      final audioPort = _audioService!.actualPort;

      _roomId = RoomDiscoveryService.generateId();
      await _discovery.startAdvertising(
        id: _roomId!,
        name: 'MotoVox',
        ip: ip,
        port: audioPort,
      );

      if (!mounted) return;
      setState(() {
        _qrData = jsonEncode({'ip': ip, 'port': audioPort});
        _statusMsg = '$ip · Puerto $audioPort';
      });

      _audioService!.connectionState.firstWhere((c) => c).then((_) {
        if (mounted && !_navigatedToConnected) _goToConnected();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _statusMsg = 'Error: $e\n\nVuelve e intenta de nuevo.');
      }
    }
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_scanned || _connecting) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // QR ajeno a MotoVox: se ignora en vez de lanzar por tipos inesperados.
    final ip = payload['ip'];
    final port = payload['port'];
    if (ip is! String || port is! int) return;

    setState(() {
      _scanned = true;
      _connecting = true;
      _statusMsg = 'Conectando con $ip...';
    });

    try {
      _audioService = AudioRelayService();
      await _audioService!.init();
      final ok = await _audioService!.connectToHost(ip, port: port);

      if (!mounted) return;
      if (ok) {
        _goToConnected();
      } else {
        setState(() {
          _scanned = false;
          _connecting = false;
          _statusMsg = 'No se pudo conectar. Intenta de nuevo.';
        });
        await _audioService?.dispose();
        _audioService = null;
      }
    } catch (e) {
      await _audioService?.dispose();
      _audioService = null;
      if (!mounted) return;
      setState(() {
        _scanned = false;
        _connecting = false;
        _statusMsg = 'Error: $e';
      });
    }
  }

  void _goToConnected() {
    _discovery.stopAdvertising();
    _navigatedToConnected = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConnectedScreen(audio: _audioService!),
      ),
    );
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    if (!_navigatedToConnected) {
      _audioService?.dispose();
      _discovery.stopAdvertising();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MvAppBar(
        title: widget.isHost ? 'Crear sala' : 'Escanear QR',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: widget.isHost ? _buildHost() : _buildClient(),
        ),
      ),
    );
  }

  Widget _buildHost() {
    // Estado de carga
    if (_qrData == null) {
      final isError = _statusMsg != null && _statusMsg!.startsWith('Error');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isError) ...[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.redDim,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.red,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusMsg!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.red, fontSize: 13),
              ),
            ] else ...[
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.orange,
                  backgroundColor: AppColors.border,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _statusMsg ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Buscando red WiFi',
                style: TextStyle(color: AppColors.white40, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    // Estado listo con QR
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: const StatusPill(label: 'Sala activa')),
        const SizedBox(height: 12),
        const Text(
          'Comparte este código QR con tu copiloto',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.white40,
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.orangeGlow,
                  blurRadius: 48,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: QrImageView(
              data: _qrData!,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _statusMsg ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.white40,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PulsingDot(),
            const SizedBox(width: 8),
            const Text(
              'Esperando al copiloto...',
              style: TextStyle(color: AppColors.white40, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildClient() {
    if (_connecting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.orange,
                backgroundColor: AppColors.border,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _statusMsg ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _statusMsg != null && !_connecting
              ? _statusMsg!
              : 'Apunta la cámara al QR del piloto',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _statusMsg != null && _statusMsg!.contains('Error')
                ? AppColors.red
                : AppColors.white40,
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                MobileScanner(onDetect: _onQrDetected),

                // Guías de esquina
                ..._cornerGuides(),

                // Línea de escaneo animada
                AnimatedBuilder(
                  animation: _scanCtrl,
                  builder: (_, _) {
                    final topFrac = 0.18 + _scanCtrl.value * 0.64;
                    return Positioned(
                      top: null,
                      left: 20,
                      right: 20,
                      child: FractionallySizedBox(
                        heightFactor: topFrac,
                        alignment: Alignment.topCenter,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  AppColors.orange,
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.orange,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Grid sutil
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.03,
                    child: GridPaper(
                      color: Colors.white,
                      divisions: 1,
                      subdivisions: 1,
                      interval: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _cornerGuides() {
    const size = 24.0;
    const offset = 16.0;
    const w = 3.0;
    final color = AppColors.orange;

    return [
      // Esquina superior izquierda
      Positioned(
        top: offset,
        left: offset,
        child: _Corner(
          color: color,
          size: size,
          strokeWidth: w,
          top: true,
          left: true,
        ),
      ),
      // Esquina superior derecha
      Positioned(
        top: offset,
        right: offset,
        child: _Corner(
          color: color,
          size: size,
          strokeWidth: w,
          top: true,
          left: false,
        ),
      ),
      // Esquina inferior izquierda
      Positioned(
        bottom: offset,
        left: offset,
        child: _Corner(
          color: color,
          size: size,
          strokeWidth: w,
          top: false,
          left: true,
        ),
      ),
      // Esquina inferior derecha
      Positioned(
        bottom: offset,
        right: offset,
        child: _Corner(
          color: color,
          size: size,
          strokeWidth: w,
          top: false,
          left: false,
        ),
      ),
    ];
  }
}

class _Corner extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;
  final bool top;
  final bool left;

  const _Corner({
    required this.color,
    required this.size,
    required this.strokeWidth,
    required this.top,
    required this.left,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          strokeWidth: strokeWidth,
          top: top,
          left: left,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool top;
  final bool left;

  const _CornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final w = size.width;
    final h = size.height;

    if (top && left) {
      canvas.drawLine(Offset(0, h), Offset(0, 0), paint);
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
    } else if (top && !left) {
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
    } else if (!top && left) {
      canvas.drawLine(Offset(0, 0), Offset(0, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    } else {
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: 0.4 + 0.6 * _ctrl.value,
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.orange,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
