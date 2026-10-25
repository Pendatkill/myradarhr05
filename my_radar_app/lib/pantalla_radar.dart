import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'enlace.dart';
import 'estado.dart';
import 'radar_painter.dart';
import 'tema.dart';

class PantallaRadar extends StatefulWidget {
  const PantallaRadar({super.key, required this.enlace});
  final Enlace enlace;

  @override
  State<PantallaRadar> createState() => _PantallaRadarState();
}

class _PantallaRadarState extends State<PantallaRadar> with SingleTickerProviderStateMixin {
  final _estado = RadarEstado();
  final _fotograma = ValueNotifier<int>(0);
  late final Ticker _ticker;
  StreamSubscription<String>? _sub;
  bool _perdido = false;
  bool _cerrado = false;
  int _contador = 0;

  @override
  void initState() {
    super.initState();
    _estado.alAlertar = (_, _) {
      if (_estado.ajustes.vibrar) HapticFeedback.heavyImpact();
    };
    _sub = widget.enlace.lineas.listen(
      (l) {
        if (!_estado.procesarLinea(l) && (l.startsWith('INFO') || l.startsWith('OK'))) _aviso(l);
      },
      onError: (_) => _marcarPerdido(),
      onDone: _marcarPerdido,
    );
    // Radar a 60 fps; panel de datos a ~10 fps
    _ticker = createTicker((_) {
      _fotograma.value++;
      if (++_contador % 6 == 0) setState(() {});
    })
      ..start();
  }

  void _marcarPerdido() {
    if (mounted && !_cerrado) setState(() => _perdido = true);
  }

  Future<void> _cerrarEnlace() async {
    if (_cerrado) return;
    _cerrado = true;
    await _sub?.cancel();
    await widget.enlace.cerrar();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fotograma.dispose();
    _cerrarEnlace();
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // ---------------------------------------------------------------- acciones
  void _menu(String opcion) {
    switch (opcion) {
      case 'ajustes':
        _ajustes();
      case 'limpiar':
        _estado.limpiar();
      case 'wifi':
        _configurarWifi();
      case 'olvidar':
        _enviar('WIFIOFF', 'Radar sin WiFi de casa. Se reinicia y solo crea la red «$ssidRedPropia».');
      case 'info':
        _enviar('INFO', null);
    }
  }

  Future<void> _enviar(String cmd, String? ok) async {
    try {
      await widget.enlace.enviar(cmd);
      if (ok != null) _aviso(ok);
    } catch (e) {
      _aviso('No se pudo enviar la orden: $e');
    }
  }

  Future<void> _configurarWifi() async {
    final ssid = TextEditingController(), clave = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WIFI DEL RADAR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('El radar se unirá a esta red y seguirá creando «$ssidRedPropia».', style: mono(12, color: Paleta.apagado)),
            const SizedBox(height: 14),
            TextField(controller: ssid, style: mono(15), decoration: const InputDecoration(labelText: 'NOMBRE DE LA RED')),
            const SizedBox(height: 10),
            TextField(controller: clave, obscureText: true, style: mono(15), decoration: const InputDecoration(labelText: 'CLAVE')),
          ],
        ),
        actions: [
          BotonTactico('Cancelar', onPressed: () => Navigator.pop(ctx, false)),
          BotonTactico('Enviar', principal: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    final s = ssid.text.trim(), c = clave.text;
    ssid.dispose();
    clave.dispose();
    if (enviar != true) return;
    if (s.isEmpty || s.contains('|') || c.contains('|')) {
      _aviso('El nombre no puede estar vacío y ni el nombre ni la clave pueden contener «|».');
      return;
    }
    await _enviar('WIFI|$s|$c',
        'Radar reiniciándose en «$s». Conecta el móvil a esa red y búscalo en CANAL 2.');
  }

  void _ajustes() {
    final aj = _estado.ajustes;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void cambiar(VoidCallback f) {
          set(f);
          setState(() {});
        }

        Widget deslizador(String titulo, String valor, double v, double mn, double mx, int div, ValueChanged<double> f) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(titulo, style: rotulo(color: Paleta.caqui))),
                Text(valor, style: mono(14, color: Paleta.verde)),
              ]),
              Slider(value: v, min: mn, max: mx, divisions: div, onChanged: (x) => cambiar(() => f(x))),
            ]);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('PARÁMETROS', style: estarcido(22)),
              const SizedBox(height: 12),
              deslizador('ALCANCE', '${aj.alcance} cm', aj.alcance.toDouble(), 50, 400, 35,
                  (x) => aj.alcance = x.round()),
              deslizador('PERÍMETRO DE ALERTA', '${aj.perimetro} cm', aj.perimetro.toDouble(), 5, 100, 19,
                  (x) => aj.perimetro = x.round()),
              deslizador('PERSISTENCIA DE ECOS', '${aj.persistencia.round()} s', aj.persistencia, 1, 12, 11,
                  (x) => aj.persistencia = x),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('INVERTIR LADOS', style: rotulo(color: Paleta.caqui)),
                value: aj.invertir,
                onChanged: (v) => cambiar(() => aj.invertir = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('VIBRAR EN ALERTA', style: rotulo(color: Paleta.caqui)),
                value: aj.vibrar,
                onChanged: (v) => cambiar(() => aj.vibrar = v),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------- interfaz
  @override
  Widget build(BuildContext context) {
    final ecos = _estado.ecos();
    final contactos = _estado.contactos(ecos);
    return PopScope(
      onPopInvokedWithResult: (salio, _) {
        if (salio) _cerrarEnlace();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _barraSuperior(),
              _franja(),
              Expanded(
                child: LayoutBuilder(builder: (ctx, bc) {
                  final apaisado = bc.maxWidth > bc.maxHeight * 1.15;
                  if (apaisado) {
                    return Row(children: [
                      Expanded(child: _pantalla()),
                      SizedBox(width: min(360, bc.maxWidth * .4), child: _panel(ecos, contactos)),
                    ]);
                  }
                  return Column(children: [
                    SizedBox(height: min(bc.maxWidth * .72, bc.maxHeight * .5), child: _pantalla()),
                    Expanded(child: _panel(ecos, contactos)),
                  ]);
                }),
              ),
              _pie(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraSuperior() {
    final (texto, color) = switch (null) {
      _ when _perdido => ('ENLACE PERDIDO', Paleta.rojo),
      _ when widget.enlace.tipo == TipoEnlace.simulacion => ('SIMULACIÓN', Paleta.ambar),
      _ when _estado.recibiendo => ('EN VIVO · ${widget.enlace.etiqueta}', Paleta.verde),
      _ => (_estado.ultimo == 0 ? 'ESPERANDO DATOS' : 'SIN DATOS', Paleta.ambar),
    };
    final parpadeo = _estado.recibiendo && (_contador ~/ 30).isEven;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: const BoxDecoration(color: Paleta.panel, border: Border(bottom: BorderSide(color: Paleta.linea))),
      child: Row(children: [
        IconButton(
          tooltip: 'Volver a canales',
          icon: const Icon(Icons.arrow_back, color: Paleta.verde),
          onPressed: () => Navigator.maybePop(context),
        ),
        Image.asset('assets/antena.png', height: 30),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text('MY RADAR', style: estarcido(20))),
            Text('by $desarrollador', style: mono(11, color: Paleta.ambar)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: color)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7, color: parpadeo ? color : color.withValues(alpha: .35)),
            const SizedBox(width: 6),
            Text(texto, style: mono(11, color: color, espaciado: .8)),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Paleta.verde),
          onSelected: _menu,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'ajustes', child: Text('PARÁMETROS')),
            const PopupMenuItem(value: 'limpiar', child: Text('LIMPIAR ECOS')),
            if (widget.enlace.tipo != TipoEnlace.simulacion) ...[
              const PopupMenuItem(value: 'info', child: Text('ESTADO DEL RADAR')),
              const PopupMenuItem(value: 'wifi', child: Text('CONFIGURAR WIFI DEL RADAR')),
              const PopupMenuItem(value: 'olvidar', child: Text('OLVIDAR WIFI DEL RADAR')),
            ],
          ],
        ),
      ]),
    );
  }

  Widget _franja() {
    final aj = _estado.ajustes;
    return Container(
      color: Paleta.oliva,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Text(grupoFechaHora(DateTime.now()), style: mono(11, color: Paleta.caqui)),
        const Spacer(),
        Flexible(
          child: Text('ALC ${aj.alcance} · PER ${aj.perimetro} cm · ${widget.enlace.nombre}',
              overflow: TextOverflow.ellipsis, style: mono(11, color: Paleta.caqui)),
        ),
      ]),
    );
  }

  Widget _pantalla() {
    final alerta = _estado.enAlerta;
    final encendido = (_contador ~/ 20).isEven;
    return Stack(children: [
      Positioned.fill(
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: alerta && encendido ? Paleta.rojo : Paleta.linea, width: alerta ? 2 : 1),
          ),
          child: CustomPaint(painter: RadarPainter(_estado, repaint: _fotograma)),
        ),
      ),
      if (alerta)
        Positioned(
          top: 18,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xEE2A0B08),
                border: Border.all(color: Paleta.rojo, width: 1.5),
              ),
              child: Text('⚠ CONTACTO EN PERÍMETRO · ${_estado.dist} cm',
                  style: cond(15, color: encendido ? Paleta.rojo : const Color(0xFFC0463A), peso: FontWeight.w700, espaciado: 1.5)),
            ),
          ),
        ),
      if (_perdido)
        Positioned.fill(
          child: Container(
            color: const Color(0xD90A0E09),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Marco(
              color: Paleta.rojo,
              titulo: 'ENLACE PERDIDO',
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('El radar ha dejado de responder. Comprueba que sigue encendido y dentro de alcance.',
                    style: mono(13)),
                const SizedBox(height: 14),
                BotonTactico('Volver a canales', principal: true, onPressed: () => Navigator.maybePop(context)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _dato(String titulo, String valor, {String? unidad, Color color = Paleta.verde, String? sub}) {
    return Marco(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: rotulo()),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: valor, style: mono(30, color: color)),
            if (unidad != null) TextSpan(text: ' $unidad', style: mono(13, color: Paleta.apagado)),
          ])),
        ),
        if (sub != null) Text(sub, style: mono(11, color: Paleta.apagado), overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _panel(List<Eco> ecos, List<Contacto> contactos) {
    final aj = _estado.ajustes;
    final hayDist = _estado.dist > 0 && _estado.dist <= aj.alcance;
    final amenaza = _estado.amenaza(contactos);
    final (txtAmenaza, colAmenaza) = switch (amenaza) {
      Amenaza.ninguna => ('NULA', Paleta.verdeTenue),
      Amenaza.baja => ('BAJA', Paleta.verde),
      Amenaza.media => ('MEDIA', Paleta.ambar),
      Amenaza.alta => ('ALTA', Paleta.rojo),
    };
    final cercano = contactos.isEmpty ? null : contactos.reduce((a, b) => a.dist <= b.dist ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.0,
          children: [
            _dato('RUMBO', _estado.ang.toString().padLeft(3, '0'), unidad: '°'),
            _dato('DISTANCIA', hayDist ? '${_estado.dist}' : '---',
                unidad: hayDist ? 'cm' : null,
                color: hayDist && _estado.dist <= aj.perimetro ? Paleta.rojo : Paleta.verde,
                sub: hayDist ? 'eco ${_estado.dist * 58} µs' : 'sin retorno'),
            _dato('CONTACTOS', '${contactos.length}', color: Paleta.ambar, sub: '${ecos.length} ecos'),
            _dato('AMENAZA', txtAmenaza, color: colAmenaza),
          ],
        ),
        const SizedBox(height: 8),
        Marco(
          titulo: 'CONTACTO MÁS PRÓXIMO',
          color: Paleta.ambar,
          child: cercano == null
              ? Text('Sector despejado', style: mono(15, color: Paleta.verdeTenue))
              : Row(children: [
                  Text(cercano.indicativo, style: estarcido(22, color: Paleta.ambar)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('${cercano.dist} cm · RUMBO ${cercano.ang.toString().padLeft(3, '0')}°',
                        style: mono(15, color: cercano.dist <= aj.perimetro ? Paleta.rojo : Paleta.caqui)),
                  ),
                ]),
        ),
        const SizedBox(height: 8),
        Marco(
          titulo: 'PROXIMIDAD POR RUMBO',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(height: 70, child: CustomPaint(painter: PerfilPainter(_estado, ecos))),
            const SizedBox(height: 4),
            Row(children: [
              Text('IZQ', style: rotulo()),
              const Spacer(),
              Text('ALTURA = PROXIMIDAD', style: rotulo()),
              const Spacer(),
              Text('DER', style: rotulo()),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        Marco(
          titulo: 'TELEMETRÍA',
          child: Row(children: [
            Expanded(child: _telemetria('MED/S', _estado.medidasPorSegundo.toStringAsFixed(1))),
            Expanded(child: _telemetria('BARRIDOS', '${_estado.barridos}')),
            Expanded(child: _telemetria('ENLACE', widget.enlace.etiqueta)),
          ]),
        ),
        const SizedBox(height: 8),
        Marco(
          titulo: 'BITÁCORA DE ALERTAS',
          color: Paleta.rojo,
          child: _estado.bitacora.isEmpty
              ? Text('Sin incidencias', style: mono(13, color: Paleta.apagado))
              : Column(
                  children: [
                    for (final ev in _estado.bitacora.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Text(horaLocal(ev.hora), style: mono(12, color: Paleta.apagado)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                'CONTACTO A ${ev.dist} cm · RUMBO ${ev.ang.toString().padLeft(3, '0')}°',
                                style: mono(12)),
                          ),
                        ]),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _telemetria(String t, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: rotulo()),
        Text(v, style: mono(18, color: Paleta.caqui)),
      ]);

  Widget _pie() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(color: Paleta.panel, border: Border(top: BorderSide(color: Paleta.linea))),
      child: Row(children: [
        const FirmaDesarrollador(compacta: true),
        const Spacer(),
        Text('HC-SR04 · 40 kHz', style: mono(11, color: Paleta.apagado)),
      ]),
    );
  }
}
