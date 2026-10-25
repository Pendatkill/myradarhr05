import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pantalla_conexion.dart';
import 'tema.dart';

/// My Radar by pendatkill_dev — consola Android para el radar ultrasónico ESP32.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Paleta.fondo,
    systemNavigationBarColor: Paleta.fondo,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyRadarApp());
}

class MyRadarApp extends StatelessWidget {
  const MyRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Radar',
      debugShowCheckedModeBanner: false,
      theme: temaMilitar(),
      home: const PantallaConexion(),
    );
  }
}
