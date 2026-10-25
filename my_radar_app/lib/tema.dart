import 'package:flutter/material.dart';

/// Paleta de consola táctica: negro oliva, fósforo de visión nocturna,
/// ámbar para contactos y rojo para amenazas.
class Paleta {
  static const fondo = Color(0xFF0A0E09);
  static const panel = Color(0xFF10160E);
  static const linea = Color(0xFF2A3824);
  static const oliva = Color(0xFF3D4A26);
  static const verde = Color(0xFFA8E05F);
  static const verdeTenue = Color(0xFF5E7F3A);
  static const ambar = Color(0xFFFFB000);
  static const rojo = Color(0xFFFF4D3D);
  static const caqui = Color(0xFFD6D3B4);
  static const apagado = Color(0xFF8A8F72);
}

const fStencil = 'SairaStencil';
const fCond = 'SairaCondensed';
const fMono = 'ShareTechMono';

const desarrollador = 'pendatkill_dev';
const versionApp = '1.0.0';

TextStyle mono(double size, {Color color = Paleta.caqui, double espaciado = 0}) => TextStyle(
      fontFamily: fMono,
      fontSize: size,
      color: color,
      letterSpacing: espaciado,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle cond(double size, {Color color = Paleta.caqui, FontWeight peso = FontWeight.w600, double espaciado = 0.5}) =>
    TextStyle(fontFamily: fCond, fontSize: size, color: color, fontWeight: peso, letterSpacing: espaciado);

TextStyle estarcido(double size, {Color color = Paleta.verde}) =>
    TextStyle(fontFamily: fStencil, fontSize: size, color: color, letterSpacing: 2, height: 1);

/// Rótulo en mayúsculas espaciadas, como las serigrafías de un equipo.
TextStyle rotulo({Color color = Paleta.apagado}) =>
    cond(11.5, color: color, peso: FontWeight.w700, espaciado: 2.2);

ThemeData temaMilitar() {
  const esquema = ColorScheme.dark(
    primary: Paleta.verde,
    onPrimary: Paleta.fondo,
    secondary: Paleta.ambar,
    error: Paleta.rojo,
    surface: Paleta.panel,
    onSurface: Paleta.caqui,
  );
  const sinRadio = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Paleta.fondo,
    fontFamily: fCond,
    splashFactory: InkRipple.splashFactory,
    dividerColor: Paleta.linea,
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Paleta.verde),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Paleta.fondo,
      labelStyle: rotulo(),
      hintStyle: mono(14, color: Paleta.apagado),
      enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Paleta.linea)),
      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Paleta.verde)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Paleta.panel,
      contentTextStyle: mono(13),
      shape: const RoundedRectangleBorder(side: BorderSide(color: Paleta.verdeTenue)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Paleta.panel,
      shape: const RoundedRectangleBorder(side: BorderSide(color: Paleta.verdeTenue)),
      titleTextStyle: estarcido(20),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Paleta.panel, shape: sinRadio),
    popupMenuTheme: PopupMenuThemeData(
      color: Paleta.panel,
      shape: const RoundedRectangleBorder(side: BorderSide(color: Paleta.linea)),
      textStyle: cond(15),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Paleta.verde,
      inactiveTrackColor: Paleta.linea,
      thumbColor: Paleta.verde,
      overlayColor: Color(0x22A8E05F),
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Paleta.fondo : Paleta.apagado),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Paleta.verde : Paleta.linea),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Paleta.verde, linearTrackColor: Paleta.linea),
  );
}

/// Panel con filete fino y escuadras en las esquinas.
class Marco extends StatelessWidget {
  const Marco({
    super.key,
    required this.child,
    this.titulo,
    this.accion,
    this.color = Paleta.verde,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
  });

  final Widget child;
  final String? titulo;
  final Widget? accion;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _Escuadras(color),
      child: Container(
        decoration: BoxDecoration(color: Paleta.panel, border: Border.all(color: Paleta.linea)),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titulo != null) ...[
              Row(children: [
                Container(width: 6, height: 6, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(titulo!, style: rotulo())),
                ?accion,
              ]),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _Escuadras extends CustomPainter {
  _Escuadras(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const l = 10.0;
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(0, l)
        ..lineTo(0, 0)
        ..lineTo(l, 0)
        ..moveTo(w - l, 0)
        ..lineTo(w, 0)
        ..lineTo(w, l)
        ..moveTo(w, h - l)
        ..lineTo(w, h)
        ..lineTo(w - l, h)
        ..moveTo(l, h)
        ..lineTo(0, h)
        ..lineTo(0, h - l),
      p,
    );
  }

  @override
  bool shouldRepaint(_Escuadras old) => old.color != color;
}

/// Botón de mando: esquinas rectas y texto espaciado.
class BotonTactico extends StatelessWidget {
  const BotonTactico(this.texto, {super.key, this.onPressed, this.principal = false, this.icono, this.color = Paleta.verde});

  final String texto;
  final VoidCallback? onPressed;
  final bool principal;
  final IconData? icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final estilo = ButtonStyle(
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      textStyle: WidgetStatePropertyAll(cond(14, peso: FontWeight.w700, espaciado: 1.8)),
      side: WidgetStatePropertyAll(BorderSide(color: onPressed == null ? Paleta.linea : color)),
      foregroundColor: WidgetStatePropertyAll(
          onPressed == null ? Paleta.apagado : (principal ? Paleta.fondo : color)),
      backgroundColor: WidgetStatePropertyAll(
          principal && onPressed != null ? color : Colors.transparent),
    );
    final etiqueta = Text(texto.toUpperCase());
    return icono == null
        ? OutlinedButton(onPressed: onPressed, style: estilo, child: etiqueta)
        : OutlinedButton.icon(onPressed: onPressed, style: estilo, icon: Icon(icono, size: 18), label: etiqueta);
  }
}

/// Firma del desarrollador con su marca (el cuervo sobre Python).
class FirmaDesarrollador extends StatelessWidget {
  const FirmaDesarrollador({super.key, this.compacta = false});
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: const Color(0xFF26331E), border: Border.all(color: Paleta.linea)),
          child: Image.asset('assets/logo_cuervo.png', height: compacta ? 18 : 26),
        ),
        const SizedBox(width: 8),
        Text.rich(TextSpan(children: [
          TextSpan(text: compacta ? 'DEV ' : 'DESARROLLADO POR ', style: rotulo()),
          TextSpan(text: desarrollador, style: mono(compacta ? 12 : 14, color: Paleta.ambar)),
        ])),
      ],
    );
  }
}

/// Grupo fecha-hora militar: DDHHMMZ MES AA (en UTC).
String grupoFechaHora(DateTime t) {
  const meses = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
  final u = t.toUtc();
  String d(int n) => n.toString().padLeft(2, '0');
  return '${d(u.day)}${d(u.hour)}${d(u.minute)}${d(u.second)}Z ${meses[u.month - 1]} ${d(u.year % 100)}';
}

String horaLocal(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
