import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class LicenseService {
  static const _keyInstallDate = 'install_date';
  static const _keyUnlocked = 'license_unlocked';
  static const _keyLastSeen = 'last_seen';
  static const int trialDays = 10;

  static Future<void> registerInstallIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyInstallDate) == null) {
      await prefs.setString(_keyInstallDate, DateTime.now().toIso8601String());
    }
  }

  // Atrasar el reloj del teléfono no devuelve días de prueba: nunca se usa
  // una fecha anterior a la última vista. Se guarda en UTC para que un cambio
  // de zona horaria no cuente como retroceso.
  // ponytail: borrar los datos de la app reinicia la prueba; evitarlo exige
  // validar contra un servidor.
  static Future<DateTime> _now(SharedPreferences prefs) async {
    final now = DateTime.now();
    final last = DateTime.tryParse(prefs.getString(_keyLastSeen) ?? '');
    if (last != null && now.isBefore(last)) return last.toLocal();
    await prefs.setString(_keyLastSeen, now.toUtc().toIso8601String());
    return now;
  }

  static Future<bool> isExpired() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_keyUnlocked) == true) return false;

    final raw = prefs.getString(_keyInstallDate);
    if (raw == null) {
      // Self-heal: si la instalación nunca se registró, el trial arranca aquí
      // (evita acceso indefinido si registerInstallIfNeeded no corrió).
      await prefs.setString(_keyInstallDate, DateTime.now().toIso8601String());
      return false;
    }

    final installDate = DateTime.parse(raw);
    final diff = (await _now(prefs)).difference(installDate).inDays;
    return diff >= trialDays;
  }

  static Future<int> daysRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyUnlocked) == true) return -1;

    final raw = prefs.getString(_keyInstallDate);
    if (raw == null) return trialDays;

    final installDate = DateTime.parse(raw);
    final used = (await _now(prefs)).difference(installDate).inDays;
    return (trialDays - used).clamp(0, trialDays);
  }

  static Future<bool> tryUnlock(String code) async {
    if (code != adminCode) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUnlocked, true);
    return true;
  }

  static Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUnlocked) ?? false;
  }
}
