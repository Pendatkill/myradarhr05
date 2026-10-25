# My Radar · app Android

Consola de estilo táctico para el radar ultrasónico ESP32, by **pendatkill_dev**. Se conecta por Bluetooth LE o WiFi; también tiene un modo de simulación sin radar.

## Compilar

Requiere Flutter 3.44 o posterior y el SDK de Android.

```sh
flutter pub get
dart run flutter_launcher_icons   # solo si cambias assets/icono*.png
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

## Código

| Archivo | Contenido |
|---|---|
| `lib/main.dart` | Arranque y tema |
| `lib/tema.dart` | Paleta, tipografías y componentes (marcos, botones, firma del desarrollador) |
| `lib/enlace.dart` | Conexiones WiFi (TCP), Bluetooth LE, simulación y descubrimiento UDP |
| `lib/estado.dart` | Medidas, ecos, agrupación en contactos, nivel de amenaza y bitácora |
| `lib/radar_painter.dart` | Dibujo de la pantalla de radar y del perfil de proximidad |
| `lib/pantalla_conexion.dart` | Selección de canal |
| `lib/pantalla_radar.dart` | Pantalla principal, parámetros y configuración WiFi del radar |
| `android/.../MainActivity.kt` | Fija la app a la WiFi «MyRadar» (que no tiene internet) y activa la recepción de difusiones UDP |

Los UUID, puertos y la red propia deben coincidir con `firmware/radar_esp32/radar_esp32.ino`.
