import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Deben coincidir con radar_esp32.ino
const ipRedPropia = '192.168.4.1';
const ssidRedPropia = 'MyRadar';
const claveRedPropia = 'pendatkill';
const puertoTcp = 3333;
const puertoUdp = 3334;
final uuidServicio = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final uuidRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
final uuidTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

const _red = MethodChannel('myradar/red');

enum TipoEnlace { bluetooth, wifi, simulacion }

/// Canal con el radar: líneas de texto en ambos sentidos.
abstract class Enlace {
  TipoEnlace get tipo;
  String get nombre;
  Stream<String> get lineas;
  Future<void> enviar(String comando);
  Future<void> cerrar();

  String get etiqueta => switch (tipo) {
        TipoEnlace.bluetooth => 'BLE',
        TipoEnlace.wifi => 'WIFI',
        TipoEnlace.simulacion => 'SIM',
      };
}

Stream<String> _aLineas(Stream<List<int>> bytes) =>
    const Utf8Decoder(allowMalformed: true).bind(bytes).transform(const LineSplitter());

// ---------------------------------------------------------------- WiFi
class EnlaceWifi extends Enlace {
  EnlaceWifi._(this._socket, this.nombre, this._fijado) : lineas = _aLineas(_socket);

  final Socket _socket;
  final bool _fijado;
  @override
  final String nombre;
  @override
  final Stream<String> lineas;
  @override
  TipoEnlace get tipo => TipoEnlace.wifi;

  static Future<EnlaceWifi> conectar(String host) async {
    // La red MyRadar no tiene internet: sin esto Android envía el tráfico por datos móviles.
    var fijado = false;
    if (host == ipRedPropia) {
      try {
        fijado = await _red.invokeMethod<bool>('usarWifi') ?? false;
      } catch (_) {}
    }
    try {
      final s = await Socket.connect(host, puertoTcp, timeout: const Duration(seconds: 5));
      s.setOption(SocketOption.tcpNoDelay, true);
      return EnlaceWifi._(s, host, fijado);
    } catch (_) {
      if (fijado) await _soltar();
      rethrow;
    }
  }

  static Future<void> _soltar() async {
    try {
      await _red.invokeMethod('soltarWifi');
    } catch (_) {}
  }

  @override
  Future<void> enviar(String comando) async {
    _socket.write('$comando\n');
    await _socket.flush();
  }

  @override
  Future<void> cerrar() async {
    _socket.destroy();
    if (_fijado) await _soltar();
  }
}

// ---------------------------------------------------------------- Bluetooth LE
class EnlaceBle extends Enlace {
  EnlaceBle._(this._disp, this._rx, this.lineas, this._subs);

  final BluetoothDevice _disp;
  final BluetoothCharacteristic _rx;
  final List<StreamSubscription> _subs;
  @override
  final Stream<String> lineas;
  @override
  TipoEnlace get tipo => TipoEnlace.bluetooth;
  @override
  String get nombre => _disp.platformName.isEmpty ? _disp.remoteId.str : _disp.platformName;

  static Future<EnlaceBle> conectar(BluetoothDevice d) async {
    // Uso personal: licencia sin ánimo de lucro de flutter_blue_plus
    await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 12));
    try {
      final servicios = await d.discoverServices();
      final svc = servicios.firstWhere((s) => s.uuid == uuidServicio,
          orElse: () => throw StateError('Ese dispositivo no es un radar MyRadar'));
      final tx = svc.characteristics.firstWhere((c) => c.uuid == uuidTx);
      final rx = svc.characteristics.firstWhere((c) => c.uuid == uuidRx);

      final bytes = StreamController<List<int>>();
      final subs = <StreamSubscription>[
        tx.onValueReceived.listen(bytes.add),
        d.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected && !bytes.isClosed) {
            bytes.addError(const SocketException('Enlace Bluetooth perdido'));
            bytes.close();
          }
        }),
      ];
      await tx.setNotifyValue(true);
      return EnlaceBle._(d, rx, _aLineas(bytes.stream), subs);
    } catch (_) {
      await d.disconnect();
      rethrow;
    }
  }

  @override
  Future<void> enviar(String comando) =>
      _rx.write(utf8.encode('$comando\n'), allowLongWrite: true);

  @override
  Future<void> cerrar() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _disp.disconnect();
  }
}

// ---------------------------------------------------------------- Simulación
class EnlaceSimulacion extends Enlace {
  EnlaceSimulacion() {
    var ang = 90, sentido = 1;
    var fase = 0.0;
    final azar = Random();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      fase += 0.004;
      final objetos = [
        (35.0, 120.0, 8),
        (130.0, 160.0, 12),
        (165.0, 70.0, 6),
        (88 + sin(fase) * 30, 26 + sin(fase * 1.7) * 14, 5), // contacto en movimiento
      ];
      var dist = -1;
      for (final (c, d, ancho) in objetos) {
        if ((ang - c).abs() <= ancho) dist = (d + azar.nextInt(7) - 3).round();
      }
      _ctrl.add('$ang,$dist');
      ang += 2 * sentido;
      if (ang >= 178 || ang <= 2) {
        sentido = -sentido;
        ang = ang.clamp(2, 178);
      }
    });
  }

  final _ctrl = StreamController<String>();
  late final Timer _timer;
  @override
  TipoEnlace get tipo => TipoEnlace.simulacion;
  @override
  String get nombre => 'Simulación';
  @override
  Stream<String> get lineas => _ctrl.stream;

  @override
  Future<void> enviar(String comando) async {
    if (comando == 'INFO') _ctrl.add('INFO ap=simulación sta=-');
  }

  @override
  Future<void> cerrar() async {
    _timer.cancel();
    await _ctrl.close();
  }
}

// ---------------------------------------------------------------- Descubrimiento
/// Escucha los anuncios `MYRADAR <ip>` que el radar emite en la WiFi de casa.
class Descubrimiento {
  RawDatagramSocket? _socket;
  final _ips = StreamController<String>.broadcast();
  Stream<String> get ips => _ips.stream;

  Future<void> iniciar() async {
    if (_socket != null) return;
    try {
      await _red.invokeMethod('multicast', true);
    } catch (_) {}
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, puertoUdp, reuseAddress: true);
      s.broadcastEnabled = true;
      s.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        final m = RegExp(r'^MYRADAR (\S+)').firstMatch(utf8.decode(dg.data, allowMalformed: true));
        if (m != null) _ips.add(m[1]!);
      });
      _socket = s;
    } catch (_) {}
  }

  Future<void> parar() async {
    _socket?.close();
    _socket = null;
    try {
      await _red.invokeMethod('multicast', false);
    } catch (_) {}
  }
}
