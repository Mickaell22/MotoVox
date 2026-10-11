import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/license_service.dart';
import '../theme.dart';
import '../widgets/mv_widgets.dart';
import 'qr_screen.dart';
import 'rooms_screen.dart';
import 'expired_screen.dart';
import 'settings_screen.dart';
import 'share_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _daysRemaining = LicenseService.trialDays;
  bool _unlocked = false;
  int _logoTapCount = 0;

  @override
  void initState() {
    super.initState();
    _checkLicense();
    _requestPermissions();
  }

  Future<void> _checkLicense() async {
    final expired = await LicenseService.isExpired();
    if (expired && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ExpiredScreen()),
      );
      return;
    }
    final days = await LicenseService.daysRemaining();
    final unlocked = await LicenseService.isUnlocked();
    if (mounted) {
      setState(() {
        _daysRemaining = days;
        _unlocked = unlocked;
      });
    }
  }

  Future<void> _requestPermissions() async {
    // notification: Android 13+ la necesita para mostrar la llamada activa.
    await [Permission.microphone, Permission.camera, Permission.notification]
        .request();
  }

  void _goToCreate() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScreen(isHost: true)),
    );
  }

  void _goToJoin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RoomsScreen()),
    );
  }

  void _shareApp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShareScreen()),
    );
  }

  void _onLogoTap() {
    _logoTapCount++;
    if (_logoTapCount >= 10) {
      _logoTapCount = 0;
      _goToSettings();
    }
  }

  void _goToSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) => _checkLicense());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MvAppBar(
        title: 'MotoVox',
        rightIcon: const Icon(
          Icons.settings_outlined,
          color: AppColors.white70,
          size: 20,
        ),
        onRight: _goToSettings,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Hero: anillos + casco
              Center(
                child: GestureDetector(
                  onTap: _onLogoTap,
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PulseRings(
                          active: true,
                          size: 180,
                          baseOpacity: 0.12,
                          duration: const Duration(milliseconds: 2200),
                        ),
                        const HelmetWidget(size: 100, animated: true),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Text(
                'MOTOVOX',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Intercomunicador para moto',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.white40,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 14),
              if (!_unlocked) _TrialBadge(days: _daysRemaining),

              const Spacer(),

              // Botones
              PrimaryBtn(
                label: 'Crear sala',
                onPressed: _goToCreate,
                icon: const Icon(Icons.add, size: 18, color: Colors.black),
              ),
              const SizedBox(height: 12),
              OutlineBtn(
                label: 'Unirse',
                onPressed: _goToJoin,
                icon: const Icon(Icons.group_outlined, size: 18),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _shareApp,
                icon: const Icon(
                  Icons.upload_outlined,
                  size: 15,
                  color: AppColors.white40,
                ),
                label: const Text(
                  'Compartir app',
                  style: TextStyle(
                    color: AppColors.white40,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrialBadge extends StatelessWidget {
  final int days;
  const _TrialBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.white12,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          days > 0 ? 'Prueba: $days días restantes' : 'Prueba vencida',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.white40,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

