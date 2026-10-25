import 'dart:math';

class Ajustes {
  int alcance = 200; // cm, igual que DIST_MAX_CM del firmware
  int perimetro = 30; // cm, distancia de alerta
  double persistencia = 4; // s que tarda un eco en desvanecerse
  bool invertir = false;
  bool vibrar = true;
}

class Eco {
  const Eco(this.ang, this.dist, this.vida);
  final int ang, dist;
  final double vida; // 1 = recién detectado, 0 = a punto de desaparecer
}

/// Grupo de ecos contiguos: un objeto.
class Contacto {
  const Contacto(this.id, this.ang, this.dist, this.vida);
  final int id, ang, dist;
  final double vida;
  String get indicativo => 'C-${id.toString().padLeft(2, '0')}';
}

class Evento {
  const Evento(this.hora, this.ang, this.dist);
  final DateTime hora;
  final int ang, dist;
}

enum Amenaza { ninguna, baja, media, alta }

/// Datos del radar a partir de las líneas "angulo,distancia".
class RadarEstado {
  final ajustes = Ajustes();
  int ang = 90, dist = -1;
  int ultimo = 0, barridos = 0;
  final estela = <int>[];
  final bitacora = <Evento>[];
  void Function(int ang, int dist)? alAlertar;

  final _puntos = <int, (int, int)>{}; // ángulo -> (distancia, instante ms)
  final _llegadas = <int>[];
  int _dir = 0, _ultimaAlerta = 0;
  int? _prev;
  bool _enAlerta = false;
  static final _patron = RegExp(r'^(-?\d+),(-?\d+)$');

  static int get _ms => DateTime.now().millisecondsSinceEpoch;

  /// Devuelve false si la línea no es una medida (respuestas INFO/OK, basura de arranque).
  bool procesarLinea(String linea) {
    final m = _patron.firstMatch(linea.trim());
    if (m == null) return false;
    final a = int.parse(m[1]!), d = int.parse(m[2]!);
    if (a < 0 || a > 180 || d < -1 || d > 1000) return false;
    _nuevoDato(a, d);
    return true;
  }

  void _nuevoDato(int a, int d) {
    final t = _ms;
    if (_prev != null) {
      final dir = (a - _prev!).sign;
      if (dir != 0 && _dir != 0 && dir != _dir) barridos++;
      if (dir != 0) _dir = dir;
    }
    _prev = a;
    ang = a;
    dist = d;
    ultimo = t;
    _llegadas.add(t);
    estela.add(a);
    if (estela.length > 40) estela.removeAt(0);
    if (d > 0 && d <= ajustes.alcance) {
      _puntos[a] = (d, t);
    } else {
      _puntos.remove(a);
    }

    final alerta = d > 0 && d <= ajustes.perimetro;
    if (alerta && !_enAlerta && t - _ultimaAlerta > 1500) {
      _ultimaAlerta = t;
      bitacora.insert(0, Evento(DateTime.now(), a, d));
      if (bitacora.length > 30) bitacora.removeLast();
      alAlertar?.call(a, d);
    }
    _enAlerta = alerta;
  }

  List<Eco> ecos() {
    final t = _ms, vida = (ajustes.persistencia * 1000).round();
    _puntos.removeWhere((_, p) => t - p.$2 > vida);
    final r = [for (final e in _puntos.entries) Eco(e.key, e.value.$1, 1 - (t - e.value.$2) / vida)];
    r.sort((x, y) => x.ang.compareTo(y.ang));
    return r;
  }

  List<Contacto> contactos(List<Eco> ecos) {
    final grupos = <List<Eco>>[];
    for (final e in ecos) {
      if (grupos.isNotEmpty) {
        final u = grupos.last.last;
        if (e.ang - u.ang <= 4 && (e.dist - u.dist).abs() <= 25) {
          grupos.last.add(e);
          continue;
        }
      }
      grupos.add([e]);
    }
    final r = <Contacto>[];
    for (final g in grupos) {
      final cercano = g.reduce((a, b) => a.dist <= b.dist ? a : b);
      final angMedio = (g.fold<int>(0, (s, e) => s + e.ang) / g.length).round();
      r.add(Contacto(r.length + 1, angMedio, cercano.dist, g.map((e) => e.vida).reduce(max)));
    }
    return r;
  }

  Amenaza amenaza(List<Contacto> cs) {
    if (cs.isEmpty) return Amenaza.ninguna;
    final d = cs.map((c) => c.dist).reduce(min);
    if (d <= ajustes.perimetro) return Amenaza.alta;
    if (d <= ajustes.perimetro * 2) return Amenaza.media;
    return Amenaza.baja;
  }

  double get medidasPorSegundo {
    final t = _ms;
    _llegadas.removeWhere((x) => t - x > 2000);
    return _llegadas.length / 2;
  }

  bool get recibiendo => _ms - ultimo < 1500;
  bool get enAlerta => dist > 0 && dist <= ajustes.perimetro && recibiendo;

  void limpiar() => _puntos.clear();
}
