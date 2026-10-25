import 'dart:math';

import 'package:flutter/material.dart';

import 'estado.dart';
import 'tema.dart';

/// Pantalla de radar semicircular con escala de rumbo, contactos y estela.
class RadarPainter extends CustomPainter {
  RadarPainter(this.e, {required Listenable repaint}) : super(repaint: repaint);

  final RadarEstado e;

  late double _cx, _cy, _r;
  late bool _inv;

  Offset _polar(num ang, double f) {
    final rad = (_inv ? 180 - ang : ang) * pi / 180;
    return Offset(_cx + _r * f * cos(rad), _cy - _r * f * sin(rad));
  }

  void _texto(Canvas c, String s, Offset pos, TextStyle st, {Alignment ancla = Alignment.center}) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();
    final dx = pos.dx - tp.width * (ancla.x + 1) / 2;
    final dy = pos.dy - tp.height * (ancla.y + 1) / 2;
    tp.paint(c, Offset(dx, dy));
  }

  Path _semicirculo(double radio) => Path()
    ..moveTo(_cx - radio, _cy)
    ..arcTo(Rect.fromCircle(center: Offset(_cx, _cy), radius: radio), pi, pi, false)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final aj = e.ajustes;
    final w = size.width, h = size.height;
    _inv = aj.invertir;
    _r = max(30.0, min(w / 2 - 34, h - 64));
    _cx = w / 2;
    _cy = (h - (_r + 34 + 26)) / 2 + _r + 34;
    final centro = Offset(_cx, _cy);

    // Cuadrícula de carta táctica
    final cuad = Paint()
      ..color = Paleta.linea.withValues(alpha: .35)
      ..strokeWidth = 1;
    for (var x = _cx % 28; x < w; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), cuad);
    }
    for (var y = _cy % 28; y < h; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(w, y), cuad);
    }

    // Plato
    final plato = _semicirculo(_r);
    canvas.drawPath(
      plato,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF1E2A15), Color(0xFF0B100A)])
            .createShader(Rect.fromCircle(center: centro, radius: _r)),
    );

    // Perímetro de alerta (relleno y borde discontinuo)
    final ra = _r * min(1.0, aj.perimetro / aj.alcance);
    canvas.drawPath(_semicirculo(ra), Paint()..color = Paleta.rojo.withValues(alpha: .10));
    final discont = Paint()
      ..color = Paleta.rojo.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var a = 0; a < 180; a += 6) {
      canvas.drawArc(Rect.fromCircle(center: centro, radius: ra), pi + a * pi / 180, 3 * pi / 180, false, discont);
    }

    // Anillos de distancia
    for (var i = 1; i <= 8; i++) {
      final rr = _r * i / 8, mayor = i.isEven;
      canvas.drawArc(
        Rect.fromCircle(center: centro, radius: rr),
        pi,
        pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 8 ? 2 : 1
          ..color = i == 8
              ? Paleta.verdeTenue
              : Paleta.verde.withValues(alpha: mayor ? .22 : .08),
      );
      if (mayor) {
        final txt = '${(aj.alcance * i / 8).round()}';
        final st = mono(10, color: Paleta.apagado);
        _texto(canvas, txt, Offset(_cx + rr, _cy + 6), st, ancla: Alignment.topCenter);
        _texto(canvas, txt, Offset(_cx - rr, _cy + 6), st, ancla: Alignment.topCenter);
      }
    }
    _texto(canvas, 'cm', Offset(_cx, _cy + 6), mono(10, color: Paleta.apagado), ancla: Alignment.topCenter);

    // Escala de rumbo: marcas cada 2°, rótulo de 3 cifras cada 30°
    for (var a = 0; a <= 180; a += 2) {
      final largo = a % 30 == 0 ? 12.0 : (a % 10 == 0 ? 7.0 : 3.0);
      canvas.drawLine(
        _polar(a, 1),
        _polar(a, 1 + largo / _r),
        Paint()
          ..strokeWidth = a % 30 == 0 ? 2 : 1
          ..color = a % 30 == 0 ? Paleta.verde : (a % 10 == 0 ? Paleta.verdeTenue : Paleta.verde.withValues(alpha: .25)),
      );
      if (a % 30 == 0) {
        if (a > 0 && a < 180) {
          canvas.drawLine(centro, _polar(a, 1), Paint()..color = Paleta.verde.withValues(alpha: .12));
        }
        _texto(canvas, a.toString().padLeft(3, '0'), _polar(a, 1 + 26 / _r), mono(11, color: Paleta.caqui));
      }
    }
    canvas.drawLine(Offset(_cx - _r - 14, _cy), Offset(_cx + _r + 14, _cy),
        Paint()
          ..color = Paleta.verdeTenue
          ..strokeWidth = 2);

    // Estela del barrido
    canvas.save();
    canvas.clipPath(plato);
    final estela = e.estela, n = estela.length;
    for (var i = 1; i < n; i++) {
      final p = Path()
        ..moveTo(_cx, _cy)
        ..lineTo(_polar(estela[i - 1], 1).dx, _polar(estela[i - 1], 1).dy)
        ..lineTo(_polar(estela[i], 1).dx, _polar(estela[i], 1).dy)
        ..close();
      canvas.drawPath(
          p,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = Paleta.verde.withValues(alpha: 0.26 * pow(i / n, 1.8).toDouble()));
    }
    canvas.restore();

    // Ecos y contactos
    final ecos = e.ecos();
    for (final p in ecos) {
      final pos = _polar(p.ang, p.dist / aj.alcance);
      final col = (p.dist <= aj.perimetro ? Paleta.rojo : Paleta.ambar).withValues(alpha: p.vida);
      canvas.drawCircle(pos, 7,
          Paint()
            ..color = col.withValues(alpha: p.vida * .35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawRect(Rect.fromCenter(center: pos, width: 5, height: 5), Paint()..color = col);
    }
    for (final c in e.contactos(ecos)) {
      final pos = _polar(c.ang, c.dist / aj.alcance);
      final col = (c.dist <= aj.perimetro ? Paleta.rojo : Paleta.ambar).withValues(alpha: max(.35, c.vida));
      // Recuadro de seguimiento
      final caja = Rect.fromCenter(center: pos, width: 18, height: 18);
      final esq = Paint()
        ..color = col
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      const l = 5.0;
      canvas.drawPath(
        Path()
          ..moveTo(caja.left, caja.top + l)
          ..lineTo(caja.left, caja.top)
          ..lineTo(caja.left + l, caja.top)
          ..moveTo(caja.right - l, caja.top)
          ..lineTo(caja.right, caja.top)
          ..lineTo(caja.right, caja.top + l)
          ..moveTo(caja.right, caja.bottom - l)
          ..lineTo(caja.right, caja.bottom)
          ..lineTo(caja.right - l, caja.bottom)
          ..moveTo(caja.left + l, caja.bottom)
          ..lineTo(caja.left, caja.bottom)
          ..lineTo(caja.left, caja.bottom - l),
        esq,
      );
      _texto(canvas, '${c.indicativo} ${c.dist}', caja.topRight + const Offset(3, -2), mono(10, color: col),
          ancla: Alignment.bottomLeft);
    }

    // Haz
    final dentro = e.dist > 0 && e.dist <= aj.alcance;
    final hasta = _polar(e.ang, dentro ? e.dist / aj.alcance : 1);
    canvas.drawLine(centro, _polar(e.ang, 1),
        Paint()
          ..color = Paleta.verde.withValues(alpha: .25)
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawLine(centro, hasta,
        Paint()
          ..color = Paleta.verde
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);
    if (dentro) {
      canvas.drawLine(hasta, _polar(e.ang, 1),
          Paint()
            ..color = Paleta.rojo.withValues(alpha: .45)
            ..strokeWidth = 1.4);
      canvas.drawCircle(hasta, 3.5, Paint()..color = Colors.white);
    }

    // Emisor
    canvas.drawRect(Rect.fromCenter(center: centro, width: 26, height: 8), Paint()..color = Paleta.verde);
    canvas.drawCircle(centro - const Offset(6, 0), 2.4, Paint()..color = Paleta.fondo);
    canvas.drawCircle(centro + const Offset(6, 0), 2.4, Paint()..color = Paleta.fondo);

    // Rótulos de lado
    final izq = _polar(180, 1), der = _polar(0, 1);
    _texto(canvas, izq.dx < _cx ? 'IZQ' : 'DER', izq + const Offset(0, -14), rotulo(), ancla: Alignment.center);
    _texto(canvas, der.dx > _cx ? 'DER' : 'IZQ', der + const Offset(0, -14), rotulo(), ancla: Alignment.center);
  }

  @override
  bool shouldRepaint(RadarPainter old) => true;
}

/// Barras de proximidad por rumbo (más alta = más cerca).
class PerfilPainter extends CustomPainter {
  PerfilPainter(this.e, this.ecos);
  final RadarEstado e;
  final List<Eco> ecos;

  @override
  void paint(Canvas canvas, Size size) {
    final aj = e.ajustes;
    final w = size.width, h = size.height;
    final linea = Paint()..color = Paleta.linea;
    for (var i = 0; i <= 4; i++) {
      canvas.drawLine(Offset(0, h * i / 4), Offset(w, h * i / 4), linea);
    }
    final ya = h * min(1.0, aj.perimetro / aj.alcance);
    for (var x = 0.0; x < w; x += 6) {
      canvas.drawLine(Offset(x, ya), Offset(x + 3, ya), Paint()..color = Paleta.rojo.withValues(alpha: .7));
    }
    double xDe(int a) => (aj.invertir ? a / 180 : 1 - a / 180) * w;
    final bw = max(2.0, w / 91 - 1);
    for (final p in ecos) {
      final bh = h * (1 - p.dist / aj.alcance);
      canvas.drawRect(
        Rect.fromLTWH(min(w - bw, xDe(p.ang)), h - bh, bw, bh),
        Paint()..color = (p.dist <= aj.perimetro ? Paleta.rojo : Paleta.ambar).withValues(alpha: .3 + .7 * p.vida),
      );
    }
    final hx = xDe(e.ang);
    canvas.drawLine(Offset(hx, 0), Offset(hx, h), Paint()..color = Paleta.verde);
  }

  @override
  bool shouldRepaint(PerfilPainter old) => true;
}
