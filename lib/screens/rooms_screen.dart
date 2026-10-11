import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_relay_service.dart';
import '../services/room_discovery_service.dart';
import '../theme.dart';
import '../widgets/mv_widgets.dart';
import 'connected_screen.dart';
import 'qr_screen.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _discovery = RoomDiscoveryService();
  List<RoomInfo> _rooms = [];
  StreamSubscription<List<RoomInfo>>? _sub;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    _sub = _discovery.startDiscovery().listen((rooms) {
      if (mounted) setState(() => _rooms = rooms);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _discovery.stopDiscovery();
    super.dispose();
  }

  Future<void> _connectTo(RoomInfo room) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = room.id);

    final audio = AudioRelayService();
    bool ok;
    try {
      await audio.init();
      ok = await audio.connectToHost(room.ip, port: room.port);
    } catch (_) {
      ok = false; // sin esto _connectingId queda trabado y nada es tocable
    }

    if (!mounted) return;

    if (ok) {
      _sub?.cancel();
      _discovery.stopDiscovery();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ConnectedScreen(audio: audio)),
      );
    } else {
      await audio.dispose();
      if (!mounted) return;
      setState(() => _connectingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo conectar a ${room.name}')),
      );
    }
  }

  void _goToQrScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScreen(isHost: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MvAppBar(
        title: 'Salas disponibles',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_rooms.isNotEmpty) ...[
                Text(
                  '${_rooms.length} sala${_rooms.length != 1 ? 's' : ''} encontrada${_rooms.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.white40,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: _rooms.isEmpty
                    ? const _SearchingPlaceholder()
                    : _RoomsList(
                        rooms: _rooms,
                        connectingId: _connectingId,
                        onTap: _connectTo,
                      ),
              ),
              _SearchingIndicator(visible: _rooms.isNotEmpty),
              const SizedBox(height: 16),
              OutlineBtn(
                label: 'Escanear QR',
                onPressed: _goToQrScan,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchingPlaceholder extends StatelessWidget {
  const _SearchingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.orange,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Buscando salas...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Asegúrate de estar en la misma red que el piloto',
          style: TextStyle(color: AppColors.white40, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SearchingIndicator extends StatefulWidget {
  final bool visible;
  const _SearchingIndicator({required this.visible});

  @override
  State<_SearchingIndicator> createState() => _SearchingIndicatorState();
}

class _SearchingIndicatorState extends State<_SearchingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              final t = _ctrl.value;
              final opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
              return Opacity(
                opacity: (0.3 + 0.7 * opacity).clamp(0.0, 1.0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'Buscando más salas...',
            style: TextStyle(color: AppColors.white40, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _RoomsList extends StatelessWidget {
  final List<RoomInfo> rooms;
  final String? connectingId;
  final void Function(RoomInfo) onTap;

  const _RoomsList({
    required this.rooms,
    required this.connectingId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final room = rooms[i];
        return _RoomCard(
          room: room,
          isConnecting: connectingId == room.id,
          disabled: connectingId != null,
          onTap: () => onTap(room),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomInfo room;
  final bool isConnecting;
  final bool disabled;
  final VoidCallback onTap;

  const _RoomCard({
    required this.room,
    required this.isConnecting,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isConnecting ? AppColors.orangeDim : AppColors.darkCard,
          border: Border.all(
            color: isConnecting
                ? AppColors.orange.withValues(alpha: 0.5)
                : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isConnecting ? AppColors.orange : AppColors.orangeDim,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.headset_mic,
                size: 20,
                color: isConnecting ? Colors.black : AppColors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    room.ip,
                    style: const TextStyle(
                      color: AppColors.white40,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            if (isConnecting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.orange,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SignalBars(level: 2),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.white40,
                    size: 16,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
