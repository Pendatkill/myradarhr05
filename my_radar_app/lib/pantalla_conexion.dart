import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'enlace.dart';
import 'pantalla_radar.dart';
import 'tema.dart';

class PantallaConexion extends StatefulWidget {
  const PantallaConexion({super.key});

  @override
  State<PantallaConexion> createState() => _PantallaConexionState();
}

class _PantallaConexionState extends State<PantallaConexion> {
  final _descubrimiento = Descubrimiento();
  final _ipManual = TextEditingController();
  final _subs = <StreamSubscription>[];
  final _ipsCasa = <String>{};
  List<ScanResult> _radaresBle = [];
  BluetoothAdapterState _adaptador = BluetoothAdapterState.unknown;
  bool _escaneando = false;
  String? _enlazando;
  late Timer _reloj;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(FlutterBluePlus.adapterState.listen((s) => setState(() => _adaptador = s)))
      ..add(FlutterBluePlus.isScanning.listen((s) => setState(() => _escaneando = s)))
      ..add(FlutterBluePlus.scanResults.listen((r) => setState(() => _radaresBle = r)))
      ..add(_descubrimiento.ips.listen((ip) {
        if (_ipsCasa.add(ip)) setState(() {});
      }));
    _descubrimiento.iniciar();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _reloj.cancel();
    _descubrimiento.parar();
    FlutterBluePlus.stopScan();
    _ipManual.dispose();
    super.dispose();
  }

  Future<void> _escanear() async {
    if (_escaneando) {
      await FlutterBluePlus.stopScan();
      return;
    }
    try {
      if (_adaptador == BluetoothAdapterState.off && Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
      await FlutterBluePlus.startScan(withServices: [uuidServicio], timeout: const Duration(seconds: 10));
    } catch (e) {
      _aviso('No se pudo escanear: ${_mensaje(e)}');
    }
  }

  Future<void> _enlazar(String etiqueta, Future<Enlace> Function() abrir) async {
    if (_enlazando != null) return;
    setState(() => _enlazando = etiqueta);
    try {
      await FlutterBluePlus.stopScan();
      final enlace = await abrir();
      if (!mounted) {
        await enlace.cerrar();
        return;
      }
      await _descubrimiento.parar();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaRadar(enlace: enlace)));
      _ipsCasa.clear();
      _descubrimiento.iniciar();
    } catch (e) {
      _aviso(etiqueta == ipRedPropia
          ? 'Sin respuesta en $ipRedPropia. Conecta el móvil a la WiFi «$ssidRedPropia» '
              '(clave $claveRedPropia) y vuelve a intentarlo.'
          : 'No se pudo enlazar con $etiqueta: ${_mensaje(e)}');
    } finally {
      if (mounted) setState(() => _enlazando = null);
    }
  }

  String _mensaje(Object e) => switch (e) {
        SocketException(:final message) => message,
        StateError(:final message) => message,
        FlutterBluePlusException(:final description) => description ?? 'error de Bluetooth',
        _ => e.toString(),
      };

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto), duration: const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _cabecera(),
            const SizedBox(height: 14),
            _franjaEstado(),
            const SizedBox(height: 16),
            _canalBluetooth(),
            const SizedBox(height: 14),
            _canalWifi(),
            const SizedBox(height: 14),
            _canalSimulacion(),
            const SizedBox(height: 28),
            Center(child: const FirmaDesarrollador()),
            const SizedBox(height: 6),
            Center(child: Text('MY RADAR v$versionApp', style: rotulo())),
          ],
        ),
      ),
    );
  }

  Widget _cabecera() {
    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const RadialGradient(colors: [Color(0xFF2A381E), Color(0xFF11180D)]),
            border: Border.all(color: Paleta.verde, width: 1.5),
          ),
          child: Image.asset('assets/antena.png'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text('MY RADAR', style: estarcido(38))),
              const SizedBox(height: 4),
              Text('SISTEMA DE DETECCIÓN ULTRASÓNICA', style: rotulo(color: Paleta.caqui)),
              const SizedBox(height: 2),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'by ', style: mono(13, color: Paleta.apagado)),
                TextSpan(text: desarrollador, style: mono(13, color: Paleta.ambar)),
              ])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _franjaEstado() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: Paleta.oliva,
        border: Border(left: BorderSide(color: Paleta.ambar, width: 3)),
      ),
      child: Row(
        children: [
          Text('ENLACE: ', style: rotulo(color: Paleta.caqui)),
          Text(_enlazando == null ? 'SIN ESTABLECER' : 'ESTABLECIENDO…',
              style: mono(12, color: _enlazando == null ? Paleta.ambar : Paleta.verde)),
          const Spacer(),
          Text(grupoFechaHora(DateTime.now()), style: mono(12, color: Paleta.caqui)),
        ],
      ),
    );
  }

  Widget _fila({required IconData icono, required String titulo, String? detalle, required Widget accion}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icono, color: Paleta.verde, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: cond(16, peso: FontWeight.w700, espaciado: 1)),
                if (detalle != null) Text(detalle, style: mono(12, color: Paleta.apagado)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          accion,
        ],
      ),
    );
  }

  Widget _botonEnlazar(String etiqueta, Future<Enlace> Function() abrir) {
    final este = _enlazando == etiqueta;
    return BotonTactico(este ? 'Enlazando' : 'Enlazar',
        principal: true, onPressed: _enlazando == null ? () => _enlazar(etiqueta, abrir) : null);
  }

  Widget _canalBluetooth() {
    final apagado = _adaptador == BluetoothAdapterState.off;
    final noDisponible = _adaptador == BluetoothAdapterState.unavailable;
    return Marco(
      titulo: 'CANAL 1 · BLUETOOTH LE',
      accion: noDisponible
          ? null
          : BotonTactico(_escaneando ? 'Detener' : (apagado ? 'Activar' : 'Escanear'),
              icono: _escaneando ? Icons.stop : Icons.radar, onPressed: _escanear),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_escaneando) const LinearProgressIndicator(minHeight: 2),
          if (noDisponible)
            Text('Este dispositivo no tiene Bluetooth LE.', style: mono(13, color: Paleta.apagado))
          else if (_radaresBle.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                apagado
                    ? 'Bluetooth apagado. Pulsa ACTIVAR.'
                    : _escaneando
                        ? 'Buscando radares MyRadar…'
                        : 'Enciende el radar y pulsa ESCANEAR. Alcance aproximado: 10 m.',
                style: mono(13, color: Paleta.apagado),
              ),
            )
          else
            for (final r in _radaresBle)
              _fila(
                icono: Icons.bluetooth,
                titulo: r.device.platformName.isEmpty ? 'MyRadar' : r.device.platformName,
                detalle: '${r.device.remoteId.str} · ${r.rssi} dBm',
                accion: _botonEnlazar(r.device.remoteId.str, () => EnlaceBle.conectar(r.device)),
              ),
        ],
      ),
    );
  }

  Widget _canalWifi() {
    return Marco(
      titulo: 'CANAL 2 · WIFI',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fila(
            icono: Icons.wifi_tethering,
            titulo: 'RED PROPIA «$ssidRedPropia»',
            detalle: 'Clave $claveRedPropia · $ipRedPropia',
            accion: _botonEnlazar(ipRedPropia, () => EnlaceWifi.conectar(ipRedPropia)),
          ),
          const Divider(height: 14),
          if (_ipsCasa.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Escuchando radares en tu WiFi…', style: mono(13, color: Paleta.apagado)),
            )
          else
            for (final ip in _ipsCasa)
              _fila(
                icono: Icons.router,
                titulo: 'RADAR EN TU RED',
                detalle: ip,
                accion: _botonEnlazar(ip, () => EnlaceWifi.conectar(ip)),
              ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipManual,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: mono(15),
                  decoration: const InputDecoration(labelText: 'IP MANUAL', hintText: '192.168.1.50'),
                ),
              ),
              const SizedBox(width: 10),
              BotonTactico('Enlazar', onPressed: _enlazando != null
                  ? null
                  : () {
                      final ip = _ipManual.text.trim();
                      if (InternetAddress.tryParse(ip) == null) {
                        _aviso('Escribe una IP válida, por ejemplo 192.168.1.50.');
                        return;
                      }
                      _enlazar(ip, () => EnlaceWifi.conectar(ip));
                    }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _canalSimulacion() {
    return Marco(
      titulo: 'CANAL 3 · SIMULACIÓN',
      color: Paleta.ambar,
      child: _fila(
        icono: Icons.science_outlined,
        titulo: 'MODO ENTRENAMIENTO',
        detalle: 'Datos simulados, sin radar',
        accion: BotonTactico('Iniciar',
            color: Paleta.ambar,
            onPressed: _enlazando == null ? () => _enlazar('simulación', () async => EnlaceSimulacion()) : null),
      ),
    );
  }
}
