# MotoVox

App de intercomunicador para moto — piloto y copiloto, siempre abierto (sin push-to-talk), funciona sin internet.

## Principio de diseño
**Práctico y fácil de usar** — el piloto no puede distraerse. Todo debe ser 1-2 toques máximo.

## Stack actual
- **Flutter** (Android)
- **flutter_sound 9.30.x** — grabación y reproducción de audio PCM en tiempo real
- **TCP sockets (dart:io)** — transporte de audio entre dispositivos (reemplazó WebRTC)
- **Hotspot WiFi** — un teléfono crea hotspot, el otro se conecta, sin internet requerido
- **qr_flutter** — genera QR con IP+puerto para conectarse fácil
- **mobile_scanner** — escanea el QR del otro teléfono
- **RNNoise** — red neuronal de Mozilla para supresión de ruido, compilada como `.so` nativo ARM64 y llamada vía `dart:ffi`. Integrada en la llamada real.

## Flujo de conexión (UX)
```
Piloto                              Copiloto
  |                                     |
toca "Crear sala"                        |
sala anunciada por UDP                   |
QR visible como fallback                 |
  |                          toca "Unirse"
  |                          ve la sala en lista
  |                          toca la sala --------|
  |<============= audio activo =================>|
```

## Pantallas
1. **Inicio** — dos botones: "Crear sala" / "Unirse" + botón "Compartir app"
2. **QR** (host) — muestra QR + anuncia sala por UDP. (cliente) — escanea QR como fallback
3. **Salas disponibles** — lista de salas detectadas en la red, tap para conectar, botón "Escanear QR" al fondo
4. **Conectado** — estado de conexión, animación de audio, botón silenciar, botón desconectar

## Dispositivos de prueba
- 2 teléfonos Android (ADB ID: `103953736M000152`)
- Entorno de build: `/home/mickaell/Desktop/Proyectos de MICKAELL/MotoVox`
- Flutter: `/opt/flutter/bin/flutter`
- ADB: `/home/mickaell/Android/Sdk/platform-tools/adb`

## Comandos útiles
```bash
# Analizar código (sin su — flutter analyze no necesita SDK Android)
/opt/flutter/bin/flutter analyze lib/

# Build APK (solo arm64) — ANDROID_HOME requerido, NO usar su mickaell
ANDROID_HOME=/home/mickaell/Android/Sdk \
  /opt/flutter/bin/flutter build apk --split-per-abi --target-platform android-arm64

# Instalar en dispositivo
/home/mickaell/Android/Sdk/platform-tools/adb install -r \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Limpiar caché (si el build usa código viejo)
ANDROID_HOME=/home/mickaell/Android/Sdk /opt/flutter/bin/flutter clean
```

> **Importante**: `su mickaell -c "flutter build..."` falla porque el file watcher
> de Flutter choca con el entorno de root. Usar siempre `ANDROID_HOME=... /opt/flutter/bin/flutter ...`
> directamente desde root en el directorio del proyecto.

## Dependencias actuales (pubspec.yaml)
```yaml
version: 1.3.0+4

dependencies:
  flutter_sound: ^9.2.0          # resuelve a 9.30.0
  network_info_plus: ^4.1.0
  permission_handler: ^11.0.0
  qr_flutter: ^4.1.0
  mobile_scanner: ^3.5.6
  share_plus: ^7.2.2
  shared_preferences: ^2.2.3
  http: ^1.2.1
  ffi: ^2.1.0
  package_info_plus: ^8.0.0      # lee versión dinámica en settings_screen
```

## Arquitectura actual
```
Teléfono A (host/piloto)          Teléfono B (cliente/copiloto)
  crea hotspot     <--WiFi-->       se conecta al hotspot
  ServerSocket:puerto_dinámico      UDP escucha :8767
  UDP broadcast :8767 cada 2s  -->  ve sala en lista
  muestra QR (fallback)             tap sala → Socket.connect(ip, puerto)
       <-------- audio PCM16 por TCP ------->
```

### AudioRelayService (lib/services/audio_relay_service.dart)
- Puerto TCP: **dinámico** — el SO asigna uno libre con `bind(0)`. `actualPort` expone el puerto asignado.
- Formato: PCM16, **48000 Hz**, mono. RNNoise solo funciona a 48 kHz (480 muestras = 10 ms); a 16 kHz ve la voz con el espectro deformado y la suprime. No bajar la frecuencia sin agregar un resampler.
- Graba con `FlutterSoundRecorder` → stream `Uint8List` → **RnnoiseProcessor** → envía por socket
- Recibe datos del socket → `PlaybackQueue` (tope 200 ms) → `_player.feedUint8FromStream` con backpressure. **No usar `uint8ListSink`**: encola en un `StreamController` sin límite y la latencia crece sin techo durante la llamada. `PlaybackQueue` también realinea a muestras PCM16 porque TCP puede partir un chunk en un byte impar. Test en `test/playback_queue_test.dart`.
- **Detección de caída**: watchdog de 3 s sin datos recibidos → desconexión. Funciona porque siempre fluye audio: **silenciar manda ceros, no pausa el recorder** (si pausara, el otro lado lo tomaría como caída).
- **Reconexión automática** (solo cliente): tras una caída reintenta `ip:puerto` cada 2 s hasta reconectar o `dispose()`. `connectionState` emite `false`/`true` y `ConnectedScreen` muestra "Reconectando...". `_stopAudio()` guarda su future en `_stopping` y `_startAudio` lo espera, para no arrancar el recorder mientras el anterior todavía se detiene.
- **Foreground service** (`CallService.kt`, tipo `microphone`): `init()` lo arranca y `dispose()` lo detiene por el MethodChannel `com.motovox.motovox/app`. Sin él, Android 9+ corta el micrófono con la pantalla apagada (el caso normal en la moto). Retiene un wakelock parcial y un WiFi lock. Tiene que arrancarse con la app en primer plano y con el permiso de micrófono ya concedido (Android 14+); si falla, la llamada sigue con la pantalla encendida.
- `AudioSource.voice_communication` — activa AEC hardware de Android
- El host acepta UNA sola conexión (scope 1-a-1); una segunda se destruye. Al desconectarse se libera el slot y se detienen recorder y player, lo que permite reconexión limpia del mismo copiloto.
- `connectToHost` exige `port` explícito (los puertos son dinámicos; no hay default válido)
- `enableEchoCancellation: true`; `enableVoiceProcessing` y `enableNoiseSuppression` en `false` (RNNoise hace la supresión; apilar dos supresores degrada la voz)
- **Filtro de voz: RNNoise** — reemplazó el filtro biquad bandpass. Supresión ML que distingue voz de otros sonidos.

### RnnoiseProcessor (lib/services/rnnoise_processor.dart)
- Adapta chunks variables de flutter_sound (4096 bytes) al frame fijo de RNNoise (960 bytes = 480 muestras PCM16)
- Buffer interno `Uint8List _residual` — acumula el sobrante entre chunks, sin boxing ni O(n) shifts
- `process(Uint8List input)` → emite solo frames completos; el residuo (< 960 bytes) se guarda para el siguiente chunk
- **Fallback sin .so**: si `RnnoiseFfi.init()` falló (librnnoise.so no carga), `process()` devuelve el input tal cual (passthrough). Sin este guard, `processFrame()` lanzaría `LateInitializationError` en cada frame en release y la llamada quedaría muda.
- Conversión PCM16 LE ↔ float32 en rango nativo [-32768, 32767] (sin normalizar — requerido por RNNoise)
- Acceso a buffers FFI con `(pointer + i).value` (API actual de dart:ffi, sin `elementAt` deprecado)
- **No usar en AudioTestService**: el test graba a 16 kHz con NS de hardware para mostrar la calidad del micrófono, y RNNoise exige 48 kHz.

### AudioTestService (lib/services/audio_test_service.dart)
- Graba 5 segundos a archivo WAV temporal (16 kHz, con AEC/NS de hardware; la llamada real va a 48 kHz con RNNoise)
- Reproduce el archivo inmediatamente después para que el usuario oiga cómo suena
- **No aplica RNNoise** — el test muestra la calidad del hardware (AEC/NS), que ya es suficiente para evaluar el micrófono
- Estados: `idle → recording → playing → done`
- Pantalla: `lib/screens/audio_test_screen.dart` — accesible desde Configuración → sección Audio

### RoomDiscoveryService (lib/services/room_discovery_service.dart)
- Puerto UDP discovery: `8767`
- Host: broadcast UDP a `255.255.255.255:8767` cada 2s con `{id, name, ip, port}`
- Cliente: escucha `0.0.0.0:8767`, construye lista de `RoomInfo`, expira salas a los 7s sin señal
- Soporta múltiples salas simultáneas en la misma red (cada una con puerto TCP distinto)

## Estado actual (2026-05-05) ✓
- **Conexión y transmisión de voz funcionando** — 2 teléfonos por hotspot, sin internet
- **Supresión de ruido activa** — `AudioSource.voice_communication` + AEC de hardware + RNNoise ML
- **Descubrimiento automático de salas** — UDP broadcast; el copiloto ve la sala en lista sin escanear QR
- **Múltiples salas simultáneas** — puertos TCP dinámicos, cada sala independiente
- **QR como fallback** — sigue disponible en la pantalla del host
- **Test de audio** — graba 5 segundos y reproduce (acceso en Configuración → Audio)
- `NetworkInterface.list()` prioriza `192.168.43.x` (subred de hotspot Android)
- **Versión 1.3.0+4** — `package_info_plus` lee la versión dinámica en Configuración → Acerca de
- **Rediseño visual completo** — implementado desde prototipo hi-fi:
  - Tokens: bg `#0A0A0A`, surface `#141414`, card `#1C1C1C`, border `#282828`
  - `lib/widgets/mv_widgets.dart` — componentes compartidos: `MvAppBar`, `StatusPill`, `PrimaryBtn`, `OutlineBtn`, `SignalBars`, `HelmetWidget`, `PulseRings`, `AudioBarsWidget`
  - Casco vectorial fiel al diseño SVG con ondas de radio animadas
  - Pantalla conectado: barras de audio animadas (12 barras), timer MM:SS con glow naranja, anillos de pulso
  - Pantalla salas: cards con icono naranja, barras de señal, indicador pulsante
  - Pantalla QR scanner: guías de esquina naranjas + línea de escaneo animada
  - Configuración: secciones en cards con iconos en contenedores redondeados
  - Pantalla vencida: círculo rojo con icono de advertencia

## Pendiente
- **Probar RNNoise en llamada real** — pendiente de tener segundo teléfono para probar audio entre dispositivos
- Probar calidad de audio en condiciones reales (moto en movimiento)
- **Probar en hardware la versión 1.3.0**: 48 kHz + RNNoise (¿suena bien la voz o conviene reactivar el NS de hardware?), pantalla apagada con el foreground service, y reconexión al alejarse y volver
- Audio Bluetooth (casco): no hay ruteo SCO; Android puede mandar la salida por A2DP y tomar el micrófono del teléfono. Requiere probar con un casco real antes de tocarlo
- Latencia de punta a punta — no medida (la cola tiene tope de 200 ms, más el buffer de AudioTrack)
- Prueba de estabilidad conexión larga duración
- Licencia: `adminCode` va compilado en el APK (se extrae con `strings`) y borrar los datos de la app reinicia la prueba. Atrasar el reloj ya no sirve (`_now()` guarda la última fecha vista). Arreglarlo del todo exige un servidor
- Nombre de sala personalizable (actualmente "MotoVox" fijo)

## Roadmap: RNNoise (supresión de ruido ML)

RNNoise es una red neuronal recurrente (GRU) de Mozilla, ~100 KB, diseñada para separar
voz humana de cualquier otro sonido en tiempo real. Es lo que usan Discord, Zoom y similares.
Funciona en frames de **480 muestras** (10 ms a **48 kHz**; esa es la única frecuencia que soporta).

### Fase 1 — Compilar librnnoise.so para ARM64 ✓ COMPLETADA
**Resultado**: `lib/arm64-v8a/librnnoise.so` (5.75 MB) incluido en el APK.

- Fuentes en `android/app/src/main/cpp/rnnoise/` (modelo lite: `rnnoise_data_little.c`)
- `CMakeLists.txt` con `-O3 -ffast-math -DFLOAT_APPROX`
- `build.gradle.kts` con `externalNativeBuild.cmake` + `abiFilters("arm64-v8a")` (solo en cmake, NO en ndk defaultConfig — conflicto con --split-per-abi)
- Fixes aplicados: stub `x86/x86_arch_macros.h`, alias `rnnoise_data.h` → `rnnoise_data_little.h`, define `FLOAT_APPROX`
- Símbolos exportados: `rnnoise_create`, `rnnoise_destroy`, `rnnoise_process_frame`, `rnnoise_get_frame_size`

### Fase 2 — Dart FFI wrapper ✓ COMPLETADA
**Resultado**: `lib/native/rnnoise_ffi.dart` — carga `librnnoise.so`, expone `init()` / `processFrame()` / `dispose()`.

- `inputBuf` / `outputBuf`: buffers `Pointer<Float>` de 480 elementos reutilizables (sin copias extra)
- `processFrame()` retorna VAD probability 0.0–1.0
- Dependencia `ffi: ^2.1.0` agregada a `pubspec.yaml`

### Fase 3 — RnnoiseProcessor (buffer + conversión) ✓ COMPLETADA
**Resultado**: `lib/services/rnnoise_processor.dart`

- Buffer `Uint8List _residual` eficiente — sin boxing, sin O(n) shifts
- Combina residuo + nuevo chunk, procesa frames completos, guarda sobrante
- Conversión PCM16 LE ↔ float32 en rango [-32768, 32767]

### Fase 4 — Integración ✓ COMPLETADA
**Resultado**: `AudioRelayService` usa `RnnoiseProcessor` en lugar del filtro biquad.

- `AudioRelayService._applyVoiceFilter()` eliminado → delega a `_rnnoise.process(data)`
- `AudioTestService` NO usa RNNoise (audio pre-procesado por hardware confunde al estimador)
- Pendiente: probar con ruido de motor y viento en condiciones reales

## Decisiones de arquitectura
- **Se abandonó WebRTC**: UDP bloqueado en la interfaz AP de hotspot Android. TCP funciona siempre entre AP y cliente.
- **Sin push-to-talk** — distrae al conductor; siempre abierto como intercomunicador real
- **Descubrimiento por UDP broadcast** — sin tipear IP ni escanear QR; el QR queda de fallback
- **Puertos TCP dinámicos** — cada sala usa el puerto que el SO asigne, permite múltiples salas en red
- **Scope inicial**: solo piloto + copiloto (1 a 1)
- **flutter_webrtc eliminado** del proyecto — `webrtc_service.dart` y `signaling_service.dart` borrados
- **RNNoise vía dart:ffi** — elegido sobre plugins Flutter inexistentes; compila como `.so` con NDK y se llama directamente desde Dart sin overhead de platform channels
- **RNNoise a 48 kHz** — se creía que RNNoise silenciaba la voz porque le llegaba audio ya procesado por AEC/NS del hardware. La causa real era la frecuencia: se le pasaba audio a 16 kHz y el modelo está entrenado a 48 kHz. Desde 1.3.0 la llamada va a 48 kHz.
- **Solo tema oscuro** — las pantallas usan colores fijos (`Colors.white`, `AppColors.white40`) pensados para fondo negro; con `ThemeMode.system` el texto quedaba invisible en modo claro. El tema claro se eliminó.
- **Firma de release** — `android/key.properties` (ignorado en Git; plantilla en `key.properties.example`). Sin ese archivo se firma con la debug key. Cambiar de firma obliga a desinstalar las instalaciones existentes.
- **IP de sala** — el cliente usa la IP de origen del datagrama UDP (`dg.address`), no la del payload, que podía venir de otra interfaz del host.
- **Versioning**: MINOR por feature nueva, PATCH por bug fix. `package_info_plus` lee la versión dinámica.

## Hardware futuro
- ESP32-S3 (piloto) + ESP32 normal (copiloto)
- Comunicación por ESP-NOW entre cascos
- Audio directo en el casco sin depender del teléfono
- Batería LiPo en cada casco

## Expansión futura
- Grupos de motos (más de 2 participantes)
- Mayor distancia via internet
- Integración ESP32-S3
