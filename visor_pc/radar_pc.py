"""
RADAR — visor para PC
---------------------
Lee del ESP32 por USB líneas "angulo,distancia" y dibuja un radar con barrido.

Instalación:   pip install pygame pyserial
Uso:
    python radar_pc.py                 # detecta el puerto automáticamente
    python radar_pc.py --puerto COM5   # puerto concreto (Linux: /dev/ttyUSB0)
    python radar_pc.py --demo          # sin hardware, datos simulados
Opciones:  --max 200 (alcance en cm)  --alerta 30  --invertir (si izquierda/derecha salen al revés)
Teclas:    ESC salir · C limpiar puntos · F pantalla completa · I invertir izquierda/derecha
Importante: cierra el Monitor Serie del IDE de Arduino antes de abrir esta app.
"""
import argparse
import math
import os
import queue
import random
import sys
import threading
import time
from collections import deque

try:
    import pygame
except ImportError:
    sys.exit("Falta pygame:  pip install pygame")

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None

ANCHO, ALTO = 1280, 720
ALTO_CABECERA = 84
LOGO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "logo_cuervo.png")
AUTOR = "desarrollado por pendatkill_dev"
ALTO_PIE = 34
ANCHO_PANEL = 320          # se oculta si la ventana es estrecha

# Paleta "fósforo"
FONDO = (3, 10, 7)
FONDO_PANEL = (7, 19, 13)
TARJETA = (10, 28, 19)
BORDE = (24, 70, 44)
RADAR_CENTRO = (10, 38, 22)
RADAR_BORDE = (4, 16, 10)
VERDE = (70, 255, 150)
VERDE_MED = (40, 150, 90)
VERDE_OSC = (20, 66, 40)
TEXTO_SUAVE = (110, 165, 135)
ROJO = (255, 72, 72)
ROJO_OSC = (48, 12, 14)
AMBAR = (255, 192, 64)

VIDA_PUNTO = 4.0   # segundos que tarda un punto en desvanecerse
ESTELA = 40        # nº de posiciones de la estela del barrido


def mezcla(a, b, f):
    return tuple(int(x * (1 - f) + y * f) for x, y in zip(a, b))


def cargar_logo(alto):
    """Logo del cuervo sobre Python escalado a `alto` px, o None si falta el archivo."""
    try:
        img = pygame.image.load(LOGO).convert_alpha()
    except (pygame.error, FileNotFoundError):
        return None
    ancho = round(img.get_width() * alto / img.get_height())
    return pygame.transform.smoothscale(img, (ancho, alto))


# ---------------------------------------------------------------- datos
VIDS_USB_SERIE = {0x10C4, 0x1A86, 0x303A, 0x0403}  # SiLabs, WCH, Espressif, FTDI


def detectar_puerto():
    puertos = list(serial.tools.list_ports.comports())
    for p in puertos:
        if p.vid in VIDS_USB_SERIE:
            return p.device
    # Sin chip conocido: solo si hay un único candidato que no sea Bluetooth
    candidatos = [p for p in puertos if "BTHENUM" not in (p.hwid or "").upper()]
    return candidatos[0].device if len(candidatos) == 1 else None


def hilo_serie(puerto, baudios, cola, parar):
    while not parar.is_set():
        try:
            ser = serial.Serial(puerto, baudios, timeout=1)
        except Exception as e:
            cola.put(("estado", f"No se puede abrir {puerto}: {e}"))
            time.sleep(2)
            continue
        cola.put(("estado", f"Conectado a {puerto}"))
        try:
            while not parar.is_set():
                linea = ser.readline().decode(errors="ignore").strip()
                partes = linea.split(",")
                if len(partes) != 2:
                    continue
                try:
                    ang, dist = int(partes[0]), int(partes[1])
                except ValueError:
                    continue
                if 0 <= ang <= 180 and -1 <= dist <= 1000:   # descarta líneas corruptas
                    cola.put(("dato", ang, dist))
        except Exception as e:
            cola.put(("estado", f"Conexión perdida: {e}"))
            time.sleep(1)
        finally:
            ser.close()


def hilo_demo(cola, parar):
    cola.put(("estado", "MODO DEMO (datos simulados)"))
    objetos = [(35, 120, 8), (88, 25, 5), (130, 160, 12), (165, 70, 6)]
    ang, sentido = 90, 1
    while not parar.is_set():
        dist = -1
        for centro, d, ancho in objetos:
            if abs(ang - centro) <= ancho:
                dist = d + random.randint(-3, 3)
        cola.put(("dato", ang, dist))
        ang += 2 * sentido
        if ang >= 180 or ang <= 0:
            sentido = -sentido
            ang = max(0, min(180, ang))
        time.sleep(0.032)


# ---------------------------------------------------------------- dibujo
class Radar:
    def __init__(self, dist_max, alerta, invertir, origen):
        self.dist_max = dist_max
        self.alerta = alerta
        self.invertir = invertir
        self.origen = origen
        fuente = "consolas,menlo,dejavusansmono,monospace"
        self.f_peq = pygame.font.SysFont(fuente, 14)
        self.f_txt = pygame.font.SysFont(fuente, 17)
        self.f_tit = pygame.font.SysFont(fuente, 22, bold=True)
        self.f_med = pygame.font.SysFont(fuente, 26, bold=True)
        self.f_gra = pygame.font.SysFont(fuente, 38, bold=True)
        self.logo = cargar_logo(ALTO_CABECERA - 14)
        self.puntos = {}                 # angulo -> (distancia, instante)
        self.estela = deque(maxlen=ESTELA)
        self.angulo = 90
        self.distancia = -1
        self.estado = "Esperando datos..."
        self.error = False
        self.ultimo_dato = 0.0
        self.llegadas = deque()          # instantes de los últimos datos (medidas/s)
        self.tam = None
        self.recalcular()

    # ---------- geometría y capas estáticas
    def recalcular(self):
        self.p = pygame.display.get_surface()
        w, h = self.tam = self.p.get_size()
        self.panel_w = ANCHO_PANEL if w >= 900 else 0
        ancho_area = w - self.panel_w
        self.area = pygame.Rect(0, ALTO_CABECERA, ancho_area, max(1, h - ALTO_CABECERA - ALTO_PIE))
        self.cx = ancho_area // 2
        # Centrado vertical contando las etiquetas (44 px arriba, 30 px abajo)
        self.r = max(20, min(ancho_area // 2 - 60, self.area.height - 100))
        self.cy = self.area.top + (self.area.height - self.r - 74) // 2 + self.r + 44
        self.capa = pygame.Surface((w, h), pygame.SRCALPHA)
        self.fondo = self.pintar_fondo()
        self.rayas = self.pintar_rayas()

    def polar(self, ang, frac):
        a = math.radians(180 - ang if self.invertir else ang)
        return (self.cx + self.r * frac * math.cos(a),
                self.cy - self.r * frac * math.sin(a))

    def semicirculo(self, s, color, radio, ancho=0):
        pygame.draw.circle(s, color, (self.cx, self.cy), int(radio), ancho,
                           draw_top_left=True, draw_top_right=True)

    def pintar_fondo(self):
        s = pygame.Surface(self.tam)
        s.fill(FONDO)
        cx, cy, r = self.cx, self.cy, self.r

        # Plato del radar con degradado radial
        pasos = 28
        for i in range(pasos, 0, -1):
            self.semicirculo(s, mezcla(RADAR_CENTRO, RADAR_BORDE, i / pasos), r * i / pasos)

        # Zona de alerta
        ra = r * min(1, self.alerta / self.dist_max)
        self.semicirculo(s, ROJO_OSC, ra)
        self.semicirculo(s, (110, 34, 36), ra, 1)

        # Anillos de distancia, con etiqueta a ambos lados
        for i in range(1, 5):
            rr = r * i / 4
            self.semicirculo(s, VERDE_MED if i == 4 else VERDE_OSC, rr, 2 if i == 4 else 1)
            txt = f"{int(self.dist_max * i / 4)}" + (" cm" if i == 4 else "")
            for x in (cx + rr, cx - rr):
                t = self.f_peq.render(txt, True, TEXTO_SUAVE)
                s.blit(t, t.get_rect(midtop=(x, cy + 8)))

        # Marcas de ángulo cada 5°, radios y etiquetas cada 30°
        for ang in range(0, 181, 5):
            largo = 14 if ang % 30 == 0 else 8 if ang % 10 == 0 else 4
            col = VERDE_MED if ang % 30 == 0 else VERDE_OSC
            pygame.draw.line(s, col, self.polar(ang, 1), self.polar(ang, 1 + largo / r), 2 if ang % 30 == 0 else 1)
            if ang % 30 == 0:
                if 0 < ang < 180:
                    pygame.draw.line(s, VERDE_OSC, (cx, cy), self.polar(ang, 1), 1)
                t = self.f_txt.render(f"{ang}°", True, TEXTO_SUAVE)
                s.blit(t, t.get_rect(center=self.polar(ang, 1 + 34 / r)))

        pygame.draw.line(s, VERDE_MED, (cx - r - 16, cy), (cx + r + 16, cy), 2)
        pygame.draw.circle(s, VERDE_MED, (cx, cy), 5)
        return s

    def pintar_rayas(self):
        # Líneas de barrido tipo CRT, muy sutiles
        s = pygame.Surface(self.tam, pygame.SRCALPHA)
        for y in range(0, self.tam[1], 3):
            pygame.draw.line(s, (0, 0, 0, 34), (0, y), (self.tam[0], y))
        return s

    # ---------- datos
    def nuevo_dato(self, ang, dist):
        ahora = time.time()
        self.angulo, self.distancia = ang, dist
        self.estela.append(ang)
        self.ultimo_dato = ahora
        self.llegadas.append(ahora)
        if 0 < dist <= self.dist_max:
            self.puntos[ang] = (dist, ahora)
        else:
            self.puntos.pop(ang, None)

    def nuevo_estado(self, texto):
        self.estado = texto
        self.error = texto.startswith(("No se puede", "Conexión perdida"))

    def medidas_por_segundo(self, ahora):
        while self.llegadas and ahora - self.llegadas[0] > 2:
            self.llegadas.popleft()
        return len(self.llegadas) / 2

    def ecos_visibles(self, ahora):
        """Lista (angulo, distancia, intensidad) y purga los puntos caducados."""
        ecos = []
        for ang, (dist, t0) in list(self.puntos.items()):
            edad = ahora - t0
            if edad > VIDA_PUNTO:
                del self.puntos[ang]
            else:
                ecos.append((ang, dist, 1 - edad / VIDA_PUNTO))
        return sorted(ecos)

    def hay_alerta(self, ahora):
        return 0 < self.distancia <= self.alerta and ahora - self.ultimo_dato < 1.5

    # ---------- utilidades de texto
    def texto(self, fuente, s, color, **pos):
        t = fuente.render(s, True, color)
        r = t.get_rect(**pos)
        self.p.blit(t, r)
        return r

    def recortar(self, fuente, s, ancho):
        if fuente.size(s)[0] <= ancho:
            return s
        while s and fuente.size(s + "…")[0] > ancho:
            s = s[:-1]
        return s + "…"

    # ---------- dibujo por fotograma
    def dibujar(self):
        if pygame.display.get_surface().get_size() != self.tam:
            self.recalcular()
        ahora = time.time()
        ecos = self.ecos_visibles(ahora)

        self.p.blit(self.fondo, (0, 0))
        self.capa.fill((0, 0, 0, 0))
        self.dibujar_barrido()
        self.dibujar_ecos(ecos)
        self.p.blit(self.capa, (0, 0))
        self.dibujar_haz()
        self.p.blit(self.rayas, self.area.topleft, self.area)

        self.dibujar_cabecera()
        if self.panel_w:
            self.dibujar_panel(ahora, ecos)
        self.dibujar_pie()
        if self.hay_alerta(ahora):
            self.dibujar_alerta(ahora)

    def dibujar_barrido(self):
        # Estela en abanico que se apaga hacia atrás
        angs = list(self.estela)
        n = len(angs)
        for i in range(1, n):
            alfa = int(95 * (i / n) ** 1.6)
            pygame.draw.polygon(self.capa, (*VERDE, alfa),
                                [(self.cx, self.cy), self.polar(angs[i - 1], 1), self.polar(angs[i], 1)])
        # Halo del haz
        pygame.draw.line(self.capa, (*VERDE, 55), (self.cx, self.cy), self.polar(self.angulo, 1), 10)

    def dibujar_ecos(self, ecos):
        # Contorno que une ecos contiguos
        for (a0, d0, f0), (a1, d1, f1) in zip(ecos, ecos[1:]):
            if a1 - a0 <= 4 and abs(d1 - d0) <= 25:
                pygame.draw.line(self.capa, (*AMBAR, int(110 * min(f0, f1))),
                                 self.polar(a0, d0 / self.dist_max), self.polar(a1, d1 / self.dist_max), 2)
        for ang, dist, f in ecos:
            col = ROJO if dist <= self.alerta else AMBAR
            x, y = self.polar(ang, dist / self.dist_max)
            pygame.draw.circle(self.capa, (*col, int(30 * f)), (x, y), 14)
            pygame.draw.circle(self.capa, (*col, int(80 * f)), (x, y), 8)
            pygame.draw.circle(self.capa, (*col, int(255 * f)), (x, y), 4)

    def dibujar_haz(self):
        # Verde hasta el objeto, rojo tenue después
        centro = (self.cx, self.cy)
        if 0 < self.distancia <= self.dist_max:
            frac = self.distancia / self.dist_max
            pygame.draw.line(self.p, VERDE, centro, self.polar(self.angulo, frac), 3)
            pygame.draw.line(self.p, (150, 50, 50), self.polar(self.angulo, frac), self.polar(self.angulo, 1), 2)
            x, y = self.polar(self.angulo, frac)
            pygame.draw.circle(self.p, (255, 255, 255), (x, y), 3)
        else:
            pygame.draw.line(self.p, VERDE, centro, self.polar(self.angulo, 1), 3)

    def dibujar_cabecera(self):
        w = self.tam[0]
        pygame.draw.rect(self.p, FONDO_PANEL, (0, 0, w, ALTO_CABECERA))
        pygame.draw.line(self.p, BORDE, (0, ALTO_CABECERA - 1), (w, ALTO_CABECERA - 1))
        mid = ALTO_CABECERA // 2
        if self.logo:
            # Placa clara detrás para que el cuervo (negro) se distinga
            placa = self.logo.get_rect(midleft=(20, mid)).inflate(14, 6)
            pygame.draw.rect(self.p, (34, 52, 44), placa, border_radius=12)
            pygame.draw.rect(self.p, BORDE, placa, 1, border_radius=12)
            self.p.blit(self.logo, self.logo.get_rect(center=placa.center))
            x = placa.right + 16
        else:
            # Sin logo: medio disco con haz
            pygame.draw.circle(self.p, VERDE_MED, (30, mid + 8), 14, 2, draw_top_left=True, draw_top_right=True)
            pygame.draw.line(self.p, VERDE, (30, mid + 8), (40, mid - 2), 2)
            x = 54
        self.texto(self.f_med, "RADAR ULTRASÓNICO", VERDE, bottomleft=(x, mid + 4))
        self.texto(self.f_txt, AUTOR, AMBAR, topleft=(x + 1, mid + 6))
        r = self.texto(self.f_txt, time.strftime("%H:%M:%S"), TEXTO_SUAVE, midright=(w - 20, mid))
        # Chip con el origen de datos
        t = self.f_peq.render(self.origen, True, VERDE)
        chip = t.get_rect(midright=(r.left - 24, mid)).inflate(18, 10)
        pygame.draw.rect(self.p, TARJETA, chip, border_radius=10)
        pygame.draw.rect(self.p, BORDE, chip, 1, border_radius=10)
        self.p.blit(t, t.get_rect(center=chip.center))

    def tarjeta(self, x, y, w, h, titulo):
        pygame.draw.rect(self.p, TARJETA, (x, y, w, h), border_radius=10)
        pygame.draw.rect(self.p, BORDE, (x, y, w, h), 1, border_radius=10)
        self.texto(self.f_peq, titulo, TEXTO_SUAVE, topleft=(x + 14, y + 10))

    def dibujar_panel(self, ahora, ecos):
        w, h = self.tam
        x0 = w - self.panel_w
        pygame.draw.rect(self.p, FONDO_PANEL, (x0, ALTO_CABECERA, self.panel_w, h - ALTO_CABECERA - ALTO_PIE))
        pygame.draw.line(self.p, BORDE, (x0, ALTO_CABECERA), (x0, h - ALTO_PIE))
        x, cw = x0 + 16, self.panel_w - 32
        y = ALTO_CABECERA + 16

        # Conexión
        if self.error:
            col, txt = ROJO, "SIN CONEXIÓN"
        elif ahora - self.ultimo_dato < 1.5:
            col, txt = VERDE, "RECIBIENDO"
        elif self.ultimo_dato == 0:
            col, txt = AMBAR, "ESPERANDO"
        else:
            col, txt = AMBAR, "SIN DATOS"
        self.tarjeta(x, y, cw, 96, "CONEXIÓN")
        pulso = 0.5 + 0.5 * math.sin(ahora * 5) if col == VERDE else 1
        led = (x + 22, y + 46)
        pygame.draw.circle(self.p, mezcla(TARJETA, col, 0.35 * pulso), led, 11)
        pygame.draw.circle(self.p, col, led, 6)
        self.texto(self.f_med, txt, col, midleft=(x + 42, led[1]))
        detalle = f"{self.medidas_por_segundo(ahora):4.1f} med/s · {self.estado}"
        self.texto(self.f_peq, self.recortar(self.f_peq, detalle, cw - 28), TEXTO_SUAVE, topleft=(x + 14, y + 70))
        y += 96 + 12

        # Lectura actual
        self.tarjeta(x, y, cw, 104, "LECTURA ACTUAL")
        self.texto(self.f_peq, "ÁNGULO", VERDE_MED, topleft=(x + 14, y + 34))
        self.texto(self.f_gra, f"{self.angulo}°", VERDE, topleft=(x + 12, y + 52))
        if 0 < self.distancia <= self.dist_max:
            txt_d, col = f"{self.distancia} cm", ROJO if self.distancia <= self.alerta else VERDE
        else:
            txt_d, col = "---", VERDE_MED
        self.texto(self.f_peq, "DISTANCIA", VERDE_MED, topleft=(x + cw // 2, y + 34))
        self.texto(self.f_gra, txt_d, col, topleft=(x + cw // 2 - 2, y + 52))
        y += 104 + 12

        # Objeto más cercano en pantalla
        self.tarjeta(x, y, cw, 96, "OBJETO MÁS CERCANO")
        if ecos:
            ang, dist, _ = min(ecos, key=lambda e: e[1])
            col = ROJO if dist <= self.alerta else AMBAR
            r = self.texto(self.f_gra, f"{dist} cm", col, topleft=(x + 12, y + 36))
            self.texto(self.f_txt, f"a {ang}°", TEXTO_SUAVE, bottomleft=(r.right + 10, r.bottom - 6))
            self.texto(self.f_peq, f"{len(ecos)} ecos", TEXTO_SUAVE, topright=(x + cw - 14, y + 10))
        else:
            self.texto(self.f_gra, "DESPEJADO", VERDE_MED, topleft=(x + 12, y + 36))
        y += 96 + 12

        # Perfil de proximidad por ángulo
        alto = h - ALTO_PIE - 16 - y
        if alto >= 110:
            self.dibujar_perfil(x, y, cw, alto, ecos)

    def dibujar_perfil(self, x, y, w, h, ecos):
        self.tarjeta(x, y, w, h, "PROXIMIDAD POR ÁNGULO")
        g = pygame.Rect(x + 14, y + 34, w - 28, h - 62)
        pygame.draw.rect(self.p, FONDO, g, border_radius=4)
        for i in range(1, 4):
            gy = g.top + g.height * i / 4
            pygame.draw.line(self.p, VERDE_OSC, (g.left, gy), (g.right, gy))
        # Umbral de alerta
        ya = g.top + g.height * min(1, self.alerta / self.dist_max)
        pygame.draw.line(self.p, (120, 40, 40), (g.left, ya), (g.right, ya))
        # Barras: izquierda de la gráfica = izquierda del radar
        ancho_barra = max(2, g.width / 91 - 1)
        for ang, dist, f in ecos:
            pos = ang / 180 if self.invertir else 1 - ang / 180
            bx = g.left + pos * (g.width - ancho_barra)
            bh = g.height * (1 - dist / self.dist_max)
            col = ROJO if dist <= self.alerta else AMBAR
            pygame.draw.rect(self.p, mezcla(FONDO, col, 0.25 + 0.75 * f),
                             (bx, g.bottom - bh, ancho_barra, bh))
        # Posición actual del haz
        pos = self.angulo / 180 if self.invertir else 1 - self.angulo / 180
        hx = g.left + pos * g.width
        pygame.draw.line(self.p, VERDE, (hx, g.top), (hx, g.bottom), 1)
        self.texto(self.f_peq, "IZQ", TEXTO_SUAVE, topleft=(g.left, g.bottom + 6))
        self.texto(self.f_peq, "DER", TEXTO_SUAVE, topright=(g.right, g.bottom + 6))
        self.texto(self.f_peq, "más alto = más cerca", VERDE_MED, midtop=(g.centerx, g.bottom + 6))

    def dibujar_pie(self):
        w, h = self.tam
        pygame.draw.rect(self.p, FONDO_PANEL, (0, h - ALTO_PIE, w, ALTO_PIE))
        pygame.draw.line(self.p, BORDE, (0, h - ALTO_PIE), (w, h - ALTO_PIE))
        mid = h - ALTO_PIE // 2
        x = 16
        for tecla, accion in (("ESC", "salir"), ("C", "limpiar"), ("F", "pantalla completa"), ("I", "invertir")):
            t = self.f_peq.render(tecla, True, VERDE)
            caja = t.get_rect(midleft=(x + 6, mid)).inflate(12, 6)
            pygame.draw.rect(self.p, TARJETA, caja, border_radius=4)
            pygame.draw.rect(self.p, BORDE, caja, 1, border_radius=4)
            self.p.blit(t, t.get_rect(center=caja.center))
            r = self.texto(self.f_peq, accion, TEXTO_SUAVE, midleft=(caja.right + 6, mid))
            x = r.right + 20
        self.texto(self.f_peq, f"alcance {self.dist_max} cm · alerta {self.alerta} cm",
                   TEXTO_SUAVE, midright=(w - 16, mid))

    def dibujar_alerta(self, ahora):
        encendido = (ahora * 3) % 1 < 0.6
        if encendido:
            pygame.draw.rect(self.p, ROJO, self.area.inflate(-8, -8), 3, border_radius=6)
        t = self.f_med.render(f"¡OBJETO CERCA!  {self.distancia} cm", True, ROJO if encendido else (200, 60, 60))
        caja = t.get_rect(midtop=(self.area.centerx, self.area.top + 18)).inflate(32, 14)
        pygame.draw.rect(self.p, ROJO_OSC, caja, border_radius=8)
        pygame.draw.rect(self.p, ROJO, caja, 2, border_radius=8)
        self.p.blit(t, t.get_rect(center=caja.center))


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Visor de radar ESP32")
    ap.add_argument("--puerto")
    ap.add_argument("--baudios", type=int, default=115200)
    ap.add_argument("--max", type=int, default=200, help="alcance en cm")
    ap.add_argument("--alerta", type=int, default=30, help="distancia de alerta en cm")
    ap.add_argument("--invertir", action="store_true", help="espeja izquierda/derecha")
    ap.add_argument("--demo", action="store_true", help="datos simulados sin hardware")
    ap.add_argument("--captura", help=argparse.SUPPRESS)  # guarda una imagen y sale (pruebas)
    args = ap.parse_args()
    if args.max <= 0:
        sys.exit("--max debe ser mayor que 0")

    cola, parar = queue.Queue(), threading.Event()
    if args.demo:
        origen = "DEMO"
        hilo = threading.Thread(target=hilo_demo, args=(cola, parar), daemon=True)
    else:
        if serial is None:
            sys.exit("Falta pyserial:  pip install pyserial")
        puerto = args.puerto or detectar_puerto()
        if not puerto:
            sys.exit("No encuentro ningún puerto serie. Conecta el ESP32 o usa --puerto / --demo")
        origen = puerto
        hilo = threading.Thread(target=hilo_serie, args=(puerto, args.baudios, cola, parar), daemon=True)
    hilo.start()

    pygame.init()
    pygame.display.set_mode((ANCHO, ALTO), pygame.RESIZABLE)
    pygame.display.set_caption(f"Radar ESP32 — {AUTOR}")
    try:
        pygame.display.set_icon(pygame.image.load(LOGO))
    except (pygame.error, FileNotFoundError):
        pass
    radar = Radar(args.max, args.alerta, args.invertir, origen)
    reloj = pygame.time.Clock()
    inicio = time.time()

    corriendo = True
    while corriendo:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                corriendo = False
            elif ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_ESCAPE:
                    corriendo = False
                elif ev.key == pygame.K_c:
                    radar.puntos.clear()
                elif ev.key == pygame.K_f:
                    pygame.display.toggle_fullscreen()
                elif ev.key == pygame.K_i:
                    radar.invertir = not radar.invertir
                    radar.recalcular()

        while not cola.empty():
            msg = cola.get_nowait()
            if msg[0] == "dato":
                radar.nuevo_dato(msg[1], msg[2])
            else:
                radar.nuevo_estado(msg[1])

        radar.dibujar()
        pygame.display.flip()
        reloj.tick(60)

        if args.captura and time.time() - inicio > 4:
            pygame.image.save(radar.p, args.captura)
            corriendo = False

    parar.set()
    pygame.quit()


if __name__ == "__main__":
    main()
