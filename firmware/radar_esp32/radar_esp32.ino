/*
  RADAR ULTRASÓNICO — ESP32 Plus (Keyestudio)
  ------------------------------------------------
  Servo SG90 ........ io18
  Ultrasonidos TRIG . io19 (cable azul)
  Ultrasonidos ECHO . io23 (cable verde)
  LCD 1602 I2C ...... SDA io21 / SCL io22 (bus I2C)

  El servo arranca en su posición central (90°) y desde ahí
  barre a la izquierda y a la derecha (2°..178°, sin forzar los topes).

  Envía una línea por medida:  angulo,distancia_cm   (distancia = -1 si no hay eco)
    - USB serie a 115200 baudios
    - WiFi: TCP puerto 3333. El ESP32 crea siempre la red "MyRadar" (clave
      "pendatkill", IP 192.168.4.1) y, si se le ha dado una WiFi, se une también
      a ella y anuncia su IP por UDP (puerto 3334): "MYRADAR <ip>"
    - Bluetooth LE "MyRadar": servicio UART de Nordic (notificaciones en TX)

  Comandos (por TCP, BLE RX o USB, terminados en salto de línea):
    WIFI|<ssid>|<clave>   guarda la WiFi de casa y reinicia
    WIFIOFF               borra la WiFi guardada y reinicia
    INFO                  responde "INFO ap=<ip> sta=<ip|->"

  App Android: My Radar by pendatkill_dev (carpeta my_radar_app)
  Compilar con el esquema de particiones "Huge APP" (WiFi + BLE no caben en el normal).

  Librerías (Gestor de librerías del IDE de Arduino):
    - ESP32Servo         (Kevin Harrington)  — 1.x con core ESP32 2.x, >= 3.0 con core 3.x
    - LiquidCrystal I2C  (Frank de Brabander)

  Cableado: el ECHO del HC-SR04 sale a 5 V y el ESP32 solo admite 3,3 V.
  Usa un divisor:  ECHO -- 1k -- io23 -- 2k -- GND  (o un HC-SR04P a 3,3 V).
  Alimenta el servo con 5 V aparte (GND común) y un condensador de 470-1000 µF.
*/

#include <Wire.h>
#include <ESP32Servo.h>
#include <LiquidCrystal_I2C.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ---------- Pines ----------
const int PIN_SERVO = 18;
const int PIN_TRIG  = 19;   // si no mide nada, intercambia TRIG y ECHO
const int PIN_ECHO  = 23;
const int PIN_SDA   = 21;
const int PIN_SCL   = 22;

// ---------- Ajustes ----------
const uint8_t LCD_DIR     = 0x27;  // prueba 0x3F si la pantalla no muestra nada
const int ANG_CENTRO      = 90;    // posición inicial
const int ANG_IZQ         = ANG_CENTRO + 88;  // 178° (evita forzar el tope del SG90)
const int ANG_DER         = ANG_CENTRO - 88;  // 2°
const int PASO_GRADOS     = 2;     // resolución del barrido
const int ESPERA_SERVO_MS = 30;    // tiempo para que el servo llegue y se estabilice
const int DIST_MAX_CM     = 200;   // por encima se considera "sin objeto"
const int ALERTA_CM       = 30;    // la LCD avisa si hay algo más cerca
const unsigned long PERIODO_PING_MS = 60;  // mínimo entre disparos (evita ecos residuales)

// ---------- Conectividad ----------
const char* NOMBRE    = "MyRadar";      // red WiFi propia y nombre Bluetooth
const char* CLAVE_AP  = "pendatkill";   // mínimo 8 caracteres
const uint16_t PUERTO_TCP = 3333;
const uint16_t PUERTO_UDP = 3334;
const int MAX_CLIENTES = 3;
#define UUID_SERVICIO "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define UUID_RX       "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define UUID_TX       "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

LiquidCrystal_I2C lcd(LCD_DIR, 16, 2);
Servo servo;

WiFiServer servidor(PUERTO_TCP);
WiFiClient clientes[MAX_CLIENTES];
String bufClientes[MAX_CLIENTES];
WiFiUDP udp;
Preferences prefs;
BLECharacteristic* txBle = nullptr;
volatile bool bleConectado = false;
String comandoBle;
volatile bool hayComandoBle = false;
String bufSerie;

int angulo = ANG_CENTRO;
int sentido = -1;                 // -1 = primero hacia ANG_DER, +1 = hacia ANG_IZQ
int minBarrido = 9999, angMinBarrido = 0;   // objeto más cercano del barrido en curso
int minAnterior = -1,  angMinAnterior = 0;  // resultado del barrido anterior
int contadorLcd = 0;

// ---------- Envío a todos los canales ----------
void enviar(const char* linea) {
  Serial.print(linea);
  size_t n = strlen(linea);
  for (auto& c : clientes)
    if (c && c.connected()) c.write((const uint8_t*)linea, n);
  if (bleConectado && txBle) {
    txBle->setValue((uint8_t*)linea, n);
    txBle->notify();
  }
}

// ---------- Bluetooth LE ----------
class CbServidorBle : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConectado = true; }
  void onDisconnect(BLEServer* s) override {
    bleConectado = false;
    s->getAdvertising()->start();   // vuelve a ser visible para otra conexión
  }
};

class CbRxBle : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    comandoBle = c->getValue().c_str();
    hayComandoBle = true;
  }
};

void iniciarBle() {
  BLEDevice::init(NOMBRE);
  BLEDevice::setMTU(64);
  BLEServer* srv = BLEDevice::createServer();
  srv->setCallbacks(new CbServidorBle());
  BLEService* svc = srv->createService(UUID_SERVICIO);
  txBle = svc->createCharacteristic(UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  txBle->addDescriptor(new BLE2902());
  BLECharacteristic* rx = svc->createCharacteristic(
      UUID_RX, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new CbRxBle());
  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(UUID_SERVICIO);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}

// ---------- WiFi ----------
void iniciarWifi() {
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(NOMBRE, CLAVE_AP);
  prefs.begin("radar", false);
  String ssid = prefs.getString("ssid", "");
  String clave = prefs.getString("clave", "");
  if (ssid.length()) {
    WiFi.begin(ssid.c_str(), clave.c_str());
    unsigned long t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < 8000) delay(200);
  }
  servidor.begin();
  servidor.setNoDelay(true);
}

void procesarComando(String cmd) {
  cmd.trim();
  char resp[96];
  if (cmd.startsWith("WIFI|")) {
    int sep = cmd.indexOf('|', 5);
    String ssid = sep > 0 ? cmd.substring(5, sep) : cmd.substring(5);
    String clave = sep > 0 ? cmd.substring(sep + 1) : "";
    prefs.putString("ssid", ssid);
    prefs.putString("clave", clave);
    enviar("OK WIFI guardada, reiniciando\n");
    lcd.clear(); lcd.print("WiFi guardada"); lcd.setCursor(0, 1); lcd.print("Reiniciando...");
    delay(600);
    ESP.restart();
  } else if (cmd == "WIFIOFF") {
    prefs.remove("ssid");
    prefs.remove("clave");
    enviar("OK WIFI borrada, reiniciando\n");
    delay(600);
    ESP.restart();
  } else if (cmd == "INFO") {
    String sta = WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : String("-");
    snprintf(resp, sizeof(resp), "INFO ap=%s sta=%s\n", WiFi.softAPIP().toString().c_str(), sta.c_str());
    enviar(resp);
  }
}

// Acumula bytes hasta salto de línea y ejecuta el comando
void leerLineas(Stream& s, String& buf) {
  while (s.available()) {
    char c = s.read();
    if (c == '\n') { procesarComando(buf); buf = ""; }
    else if (buf.length() < 120) buf += c;
  }
}

// Clientes TCP, comandos entrantes y anuncio UDP. Se llama a menudo desde el bucle.
void atenderRed() {
  WiFiClient nuevo = servidor.available();
  if (nuevo) {
    nuevo.setNoDelay(true);
    int libre = -1;
    for (int i = 0; i < MAX_CLIENTES; i++)
      if (!clientes[i] || !clientes[i].connected()) { libre = i; break; }
    if (libre >= 0) { clientes[libre].stop(); clientes[libre] = nuevo; bufClientes[libre] = ""; }
    else nuevo.stop();
  }
  for (int i = 0; i < MAX_CLIENTES; i++)
    if (clientes[i] && clientes[i].connected()) leerLineas(clientes[i], bufClientes[i]);
  leerLineas(Serial, bufSerie);
  if (hayComandoBle) { hayComandoBle = false; procesarComando(comandoBle); }

  // En la WiFi de casa la app no conoce la IP: se anuncia cada 2 s
  static unsigned long ultimoAnuncio = 0;
  if (WiFi.status() == WL_CONNECTED && millis() - ultimoAnuncio > 2000) {
    ultimoAnuncio = millis();
    IPAddress ip = WiFi.localIP(), mascara = WiFi.subnetMask(), difusion;
    for (int i = 0; i < 4; i++) difusion[i] = ip[i] | ~mascara[i];
    udp.beginPacket(difusion, PUERTO_UDP);
    udp.printf("MYRADAR %s", ip.toString().c_str());
    udp.endPacket();
  }
}

long medirCm() {
  static unsigned long ultimoPing = 0;
  while (millis() - ultimoPing < PERIODO_PING_MS) atenderRed();
  ultimoPing = millis();

  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  // Tiempo máximo de espera ~ ida y vuelta de DIST_MAX_CM + margen
  unsigned long us = pulseIn(PIN_ECHO, HIGH, (DIST_MAX_CM + 50) * 58UL);
  if (us == 0) return -1;
  long cm = us / 58;
  if (cm < 2 || cm > DIST_MAX_CM) return -1;
  return cm;
}

void actualizarLcd(int ang, long cm) {
  char l1[17], l2[17];
  if (cm > 0) snprintf(l1, sizeof(l1), "Ang:%3d D:%3ldcm ", ang, cm);
  else        snprintf(l1, sizeof(l1), "Ang:%3d D: --- ", ang);

  if (cm > 0 && cm <= ALERTA_CM)
    snprintf(l2, sizeof(l2), "!! OBJETO %3ldcm", cm);
  else if (minAnterior > 0)
    snprintf(l2, sizeof(l2), "Min:%3dcm a %3d", minAnterior, angMinAnterior);
  else
    snprintf(l2, sizeof(l2), "Min: despejado  ");

  // Relleno a 16 caracteres para no dejar restos de la línea anterior
  lcd.setCursor(0, 0); lcd.printf("%-16s", l1);
  lcd.setCursor(0, 1); lcd.printf("%-16s", l2);
}

void finDeBarrido() {
  minAnterior    = (minBarrido < 9999) ? minBarrido : -1;
  angMinAnterior = angMinBarrido;
  minBarrido = 9999;
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);

  Wire.begin(PIN_SDA, PIN_SCL);
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0); lcd.print("  RADAR  ESP32  ");
  lcd.setCursor(0, 1); lcd.print("  Iniciando...  ");

  // El SG90 no puede informar de su posición: le mandamos el centro primero
  servo.setPeriodHertz(50);
  servo.attach(PIN_SERVO, 500, 2400);
  servo.write(ANG_CENTRO);

  iniciarWifi();
  iniciarBle();

  // Muestra cómo conectarse durante unos segundos
  lcd.clear();
  if (WiFi.status() == WL_CONNECTED) {
    lcd.print("WiFi casa:");
    lcd.setCursor(0, 1); lcd.print(WiFi.localIP());
  } else {
    lcd.print("Red: MyRadar");
    lcd.setCursor(0, 1); lcd.print(WiFi.softAPIP());
  }
  delay(2500);
  lcd.clear();
}

void loop() {
  servo.write(angulo);
  unsigned long t0 = millis();
  while (millis() - t0 < ESPERA_SERVO_MS) atenderRed();

  long cm = medirCm();
  // El servo está montado al revés que la pantalla: se informa el ángulo espejado
  int angInforme = 180 - angulo;
  char linea[24];
  snprintf(linea, sizeof(linea), "%d,%ld\n", angInforme, cm);
  enviar(linea);

  if (cm > 0 && cm < minBarrido) { minBarrido = cm; angMinBarrido = angInforme; }

  // La LCD es lenta por I2C: refresco cada 3 pasos o al instante si hay alerta
  if (++contadorLcd >= 3 || (cm > 0 && cm <= ALERTA_CM)) {
    actualizarLcd(angInforme, cm);
    contadorLcd = 0;
  }

  // Siguiente ángulo y cambio de sentido en los extremos
  angulo += sentido * PASO_GRADOS;
  if (angulo >= ANG_IZQ) { angulo = ANG_IZQ; sentido = -1; finDeBarrido(); }
  if (angulo <= ANG_DER) { angulo = ANG_DER; sentido = +1; finDeBarrido(); }
}
