#!/usr/bin/env python3
"""Draw the picture-story for the security and bootstrap deck.

Run from inside this folder:  python3 make-scenes.py

The cast (admin, machine, keys, devices, envelope, calendar, props) is defined
once as functions that return SVG fragments, so every character looks the same
in every scene. Standard library only.
"""
import math
import random

from icons import FINGERPRINT, LOCK_CLOSED, LOCK_OPEN  # Material Icons, Apache-2.0
from xml.sax.saxutils import escape

OUT = "#1b1b1b"
SW = 3
FONT = "Helvetica, Arial, sans-serif"

# palette (docs/diagram-design-guide.md section 3, plus skin and hair)
BLUE_F, BLUE_S = "#d0ebff", "#1971c2"
GREEN_F, GREEN_S = "#d3f9d8", "#2b8a3e"
AMBER_F, AMBER_S = "#fff3bf", "#e67700"
RED_F, RED_S = "#ffe3e3", "#c92a2a"
GREY_F, GREY_S = "#f8f9fa", "#868e96"
PANEL = "#f1f5fa"
SKIN, HAIR = "#f1c9a0", "#3b2a20"
SHIRT, TROUSERS = "#ff922b", "#495057"
GOLD = "#ffd43b"
TEAL = "#20c997"
CREAM = "#fff1cf"

FLOOR = 545


# ---------------------------------------------------------------- basics
def grp(body, x=0, y=0, s=1.0, rot=0, flip=False, opacity=1.0):
    t = f"translate({x:g} {y:g})"
    if rot:
        t += f" rotate({rot:g})"
    sx = -s if flip else s
    t += f" scale({sx:g} {s:g})"
    op = f' opacity="{opacity:g}"' if opacity != 1.0 else ""
    return f'<g transform="{t}"{op}>{body}</g>'


def rect(x, y, w, h, fill="none", r=0, stroke=OUT, sw=SW, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{r:g}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw:g}"{d}/>')


def circle(cx, cy, r, fill="none", stroke=OUT, sw=SW, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{sw:g}"{d}/>')


def ellipse(cx, cy, rx, ry, fill="none", stroke=OUT, sw=SW):
    return (f'<ellipse cx="{cx:g}" cy="{cy:g}" rx="{rx:g}" ry="{ry:g}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{sw:g}"/>')


def path(d, fill="none", stroke=OUT, sw=SW, dash=None, cap="round", join="round"):
    da = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw:g}" '
            f'stroke-linecap="{cap}" stroke-linejoin="{join}"{da}/>')


def line(x1, y1, x2, y2, stroke=OUT, sw=SW, dash=None):
    return path(f"M{x1:g} {y1:g} L{x2:g} {y2:g}", stroke=stroke, sw=sw, dash=dash)


def poly(pts, fill="none", stroke=OUT, sw=SW):
    p = " ".join(f"{a:g},{b:g}" for a, b in pts)
    return (f'<polygon points="{p}" fill="{fill}" stroke="{stroke}" stroke-width="{sw:g}" '
            f'stroke-linejoin="round"/>')


def text(x, y, s, size=28, anchor="middle", fill=OUT, weight="bold"):
    return (f'<text x="{x:g}" y="{y:g}" font-family="{FONT}" font-size="{size:g}" '
            f'font-weight="{weight}" text-anchor="{anchor}" fill="{fill}">{escape(s)}</text>')


def label(x, y, lines, size=28, fill="#ffffff", stroke=OUT, dash=None):
    """A pill label centred on (x, y). `lines` is a string or a list of strings."""
    if isinstance(lines, str):
        lines = [lines]
    w = max(len(l) for l in lines) * 0.58 * size + 34
    lh = size * 1.22
    h = lh * len(lines) + 16
    out = [rect(x - w / 2, y - h / 2, w, h, fill=fill, r=min(h / 2, 26), stroke=stroke, sw=2.5, dash=dash)]
    for i, l in enumerate(lines):
        ty = y - h / 2 + 8 + lh * i + size * 0.92
        out.append(text(x, ty, l, size))
    return "".join(out)


def arrow(pts, color=OUT, sw=5, dash=None, head=16):
    """Polyline arrow with a filled head at the last point."""
    d = "M" + " L".join(f"{a:g} {b:g}" for a, b in pts)
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    return path(d, stroke=color, sw=sw, dash=dash) + arrowhead(x0, y0, x1, y1, color, head)


def arrowhead(x0, y0, x1, y1, color, head=16):
    a = math.atan2(y1 - y0, x1 - x0)
    p1 = (x1, y1)
    p2 = (x1 - head * math.cos(a - 0.45), y1 - head * math.sin(a - 0.45))
    p3 = (x1 - head * math.cos(a + 0.45), y1 - head * math.sin(a + 0.45))
    return poly([p1, p2, p3], fill=color, stroke=color, sw=2)


def curve_arrow(p0, c, p1, color=OUT, sw=5, dash=None, head=16):
    d = f"M{p0[0]:g} {p0[1]:g} Q{c[0]:g} {c[1]:g} {p1[0]:g} {p1[1]:g}"
    return path(d, stroke=color, sw=sw, dash=dash) + arrowhead(c[0], c[1], p1[0], p1[1], color, head)


def circ_arrow(cx, cy, r, a0, a1, color=BLUE_S, sw=6, head=18):
    """Clockwise circular arrow from angle a0 to a1 (degrees, SVG orientation)."""
    p0 = (cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0)))
    p1 = (cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
    large = 1 if (a1 - a0) % 360 > 180 else 0
    d = f"M{p0[0]:g} {p0[1]:g} A{r:g} {r:g} 0 {large} 1 {p1[0]:g} {p1[1]:g}"
    t = math.radians(a1)
    tx, ty = -math.sin(t), math.cos(t)
    tip = (p1[0] + tx * 6, p1[1] + ty * 6)
    return path(d, stroke=color, sw=sw) + arrowhead(p1[0] - tx * 10, p1[1] - ty * 10, tip[0], tip[1], color, head)


# ------------------------------------------------------------ small props
def tick(x, y, r=26):
    k = r / 26
    chk = f"M{-11*k:g} {1*k:g} L{-3*k:g} {10*k:g} L{12*k:g} {-9*k:g}"
    return (circle(x, y, r, fill="#51cf66", sw=3)
            + grp(path(chk, stroke=OUT, sw=11 * k) + path(chk, stroke="#ffffff", sw=6 * k), x, y))


def cross(x, y, r=26, fill="#ff6b6b"):
    k = r / 26
    c = f"M{-9*k:g} {-9*k:g} L{9*k:g} {9*k:g} M{9*k:g} {-9*k:g} L{-9*k:g} {9*k:g}"
    return (circle(x, y, r, fill=fill, sw=3)
            + grp(path(c, stroke=OUT, sw=11 * k) + path(c, stroke="#ffffff", sw=6 * k), x, y))


def padlock(x, y, s=1.0, fill=AMBER_F, stroke=OUT):
    b = (path("M-10 -2 V-12 A10 10 0 0 1 10 -12 V-2", stroke=stroke, sw=5)
         + rect(-17, -3, 34, 28, fill=fill, r=5, stroke=stroke)
         + circle(0, 9, 4, fill=stroke, stroke=stroke, sw=1)
         + line(0, 10, 0, 18, stroke=stroke, sw=3))
    return grp(b, x, y, s)


def gear(x, y, r=30, teeth=8, fill="#ced4da", spin=0):
    pts = []
    n = teeth
    for i in range(n):
        a = 2 * math.pi * i / n + math.radians(spin)
        w = math.pi / n * 0.55
        for ang, rad in ((a - w * 1.1, r * 0.78), (a - w * 0.6, r), (a + w * 0.6, r), (a + w * 1.1, r * 0.78)):
            pts.append((x + rad * math.cos(ang), y + rad * math.sin(ang)))
    return poly(pts, fill=fill) + circle(x, y, r * 0.3, fill="#ffffff")


def clock(x, y, r=18):
    return (circle(x, y, r, fill="#ffffff")
            + line(x, y, x, y - r * 0.62, sw=3)
            + line(x, y, x + r * 0.45, y + r * 0.2, sw=3))


def bell(x, y, s=1.0):
    b = (path("M-13 10 Q-13 -14 0 -14 Q13 -14 13 10 L18 15 L-18 15 Z", fill=GOLD)
         + circle(0, 20, 4, fill=OUT, stroke=OUT, sw=1)
         + circle(0, -16, 3, fill=OUT, stroke=OUT, sw=1))
    return grp(b, x, y, s)


def ticket(x, y, s=1.0, used=False):
    """A short-lived ticket token with a clock. `used` draws it faded and crossed out."""
    body = (path("M0 0 H100 V22 a8 8 0 0 0 0 16 V60 H0 V38 a8 8 0 0 0 0 -16 Z",
                 fill=GREEN_F if not used else "#e9ecef", stroke=OUT if not used else GREY_S,
                 sw=SW, dash="8 6" if used else None)
            + clock(30, 30, 17)
            + line(56, 20, 88, 20, sw=4, stroke=GREEN_S if not used else GREY_S)
            + line(56, 34, 80, 34, sw=4, stroke=GREEN_S if not used else GREY_S)
            + line(56, 46, 88, 46, sw=4, stroke=GREEN_S if not used else GREY_S))
    if used:
        body += (line(-6, -6, 106, 66, stroke=RED_S, sw=7) + line(106, -6, -6, 66, stroke=RED_S, sw=7))
    return grp(body, x, y, s)


def camera(x, y, s=1.0):
    b = (rect(22, 2, 34, 18, fill="#adb5bd", r=5)
         + rect(0, 12, 100, 66, fill="#e9ecef", r=12)
         + circle(50, 46, 22, fill="#74c0fc") + circle(50, 46, 10, fill="#ffffff")
         + circle(84, 26, 4, fill=OUT, stroke=OUT, sw=1))
    return grp(b, x, y, s)


def file_locked(x, y, s=1.0):
    b = (path("M0 0 H58 L80 22 V104 H0 Z", fill="#ffffff")
         + path("M58 0 V22 H80", fill="none")
         + line(12, 40, 56, 40, sw=4, stroke=GREY_S) + line(12, 54, 64, 54, sw=4, stroke=GREY_S)
         + line(12, 68, 48, 68, sw=4, stroke=GREY_S)
         + padlock(66, 80, 1.1))
    return grp(b, x, y, s)


def qr(x, y, size=70, seed=3):
    n = 11
    c = size / n
    rnd = random.Random(seed)
    out = [rect(x - 4, y - 4, size + 8, size + 8, fill="#ffffff", stroke=OUT, sw=2)]
    finder = {(0, 0), (n - 7, 0), (0, n - 7)}

    def in_finder(i, j):
        return any(fx <= i < fx + 7 and fy <= j < fy + 7 for fx, fy in finder)

    for i in range(n):
        for j in range(n):
            if in_finder(i, j):
                continue
            if rnd.random() < 0.5:
                out.append(f'<rect x="{x + i*c:g}" y="{y + j*c:g}" width="{c:g}" height="{c:g}" fill="{OUT}"/>')
    for fx, fy in finder:
        ox, oy = x + fx * c, y + fy * c
        out.append(f'<rect x="{ox:g}" y="{oy:g}" width="{7*c:g}" height="{7*c:g}" fill="{OUT}"/>')
        out.append(f'<rect x="{ox+c:g}" y="{oy+c:g}" width="{5*c:g}" height="{5*c:g}" fill="#ffffff"/>')
        out.append(f'<rect x="{ox+2*c:g}" y="{oy+2*c:g}" width="{3*c:g}" height="{3*c:g}" fill="{OUT}"/>')
    return "".join(out)


def fingerprint(x, y, r=20):
    """Material Icons fingerprint glyph, centred on (x, y); about 2.4 r wide."""
    k = 2.4 * r / 24
    return (f'<g transform="translate({x - 12 * k:g} {y - 12 * k:g}) scale({k:g})">'
            f'<path d="{FINGERPRINT}" fill="{OUT}"/></g>')


LOCK_SIZE = 58


def vault_lock(x, y, state, size=LOCK_SIZE):
    """Vault state icon, centred on (x, y). GREEN OPEN padlock = vault open, the platform can run.
    RED CLOSED padlock = vault closed. Shape (outlined open vs filled closed) also differs."""
    d = LOCK_OPEN if state == "open" else LOCK_CLOSED
    col = GREEN_S if state == "open" else RED_S
    k = size / 24
    return (f'<g transform="translate({x - size / 2:g} {y - size / 2:g}) scale({k:g})">'
            f'<path d="{d}" fill="#ffffff" stroke="#ffffff" stroke-width="3.4" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="{col}" stroke="{OUT}" stroke-width="0.7" stroke-linejoin="round"/></g>')


# ------------------------------------------------------------------ keys
def key(kind, x, y, s=1.0, rot=0, ghost=False, opacity=1.0):
    """GOLD key = ROUND head (unlock key). TEAL key = SQUARE diamond head (recovery key).
    Head centred on (0, 0); the shaft points right."""
    fill = GOLD if kind == "gold" else TEAL
    stroke = GREY_S if ghost else OUT
    dash = "7 5" if ghost else None
    fill = "#fff9db" if (ghost and kind == "gold") else fill
    shaft = (rect(14, -6, 66, 12, fill=fill, stroke=stroke, dash=dash)
             + rect(54, 4, 9, 11, fill=fill, stroke=stroke, dash=dash)
             + rect(68, 4, 9, 17, fill=fill, stroke=stroke, dash=dash))
    if kind == "gold":
        head = circle(0, 0, 19, fill=fill, stroke=stroke, dash=dash) + circle(0, 0, 6.5, fill="#ffffff", stroke=stroke, sw=2.5)
    else:
        head = (poly([(0, -23), (23, 0), (0, 23), (-23, 0)], fill=fill, stroke=stroke)
                + poly([(0, -8), (8, 0), (0, 8), (-8, 0)], fill="#ffffff", stroke=stroke, sw=2.5))
        if ghost:
            head = head.replace(OUT, stroke)
    return grp(shaft + head, x, y, s, rot, opacity=opacity)


PASSKEY_F = "#e5dbff"


def passkey_badge(x, y, r=21, dead=False, opacity=1.0, kind="A"):
    """A round passkey badge, never a key shape. Kind A: lavender disc with a fingerprint.
    Kind B: peach disc with a double ring and three PIN dots. Two passkeys get two badges."""
    k = r / 21
    st = GREY_S if dead else OUT
    if kind == "A":
        b = (circle(0, 0, 21, fill="#e9ecef" if dead else PASSKEY_F, stroke=st, sw=3)
             + fingerprint(0, 1, 11).replace(OUT, st))
    else:
        b = (circle(0, 0, 21, fill="#e9ecef" if dead else "#ffe8cc", stroke=st, sw=3)
             + circle(0, 0, 16, fill="none", stroke=st, sw=2)
             + "".join(circle(dx, 1, 3.4, fill=st, stroke=st, sw=1) for dx in (-9, 0, 9)))
    return grp(b, x, y, k, opacity=opacity)


def keybox(x, y, s=1.0, state="okA"):
    """A small padlocked box (150 x 96) holding two keys: a teal recovery key and a small gold
    seal key copy. It carries the badge of its passkey (state ends in A or B) and lives on the
    machine, one box per enrolled passkey. States: okA, okB, deadA, deadB."""
    ok, kind = state.startswith("ok"), state[-1]
    if ok:
        b = (rect(0, 0, 150, 96, fill=BLUE_F, r=12)
             + line(0, 22, 150, 22, sw=2.5, stroke=BLUE_S)
             + key("teal", 36, 46, 0.66)
             + key("gold", 32, 76, 0.5)
             + padlock(130, 68, 1.05)
             + passkey_badge(8, 6, kind=kind))
    else:  # dead: greyed, dashed, cracked and crossed
        b = (rect(0, 0, 150, 96, fill="#e9ecef", r=12, stroke=GREY_S, dash="9 6")
             + key("teal", 36, 46, 0.66, opacity=0.35)
             + key("gold", 32, 76, 0.5, opacity=0.35)
             + padlock(130, 68, 1.05, fill="#dee2e6", stroke=GREY_S)
             + passkey_badge(8, 6, dead=True, kind=kind)
             + path("M66 -4 L78 26 L60 44 L80 70 L70 100", stroke=RED_S, sw=5)
             + cross(82, 48, 24))
    return grp(b, x, y, s)


# --------------------------------------------------------------- devices
def phone(x, y, s=1.0, screen="", opacity=1.0, rot=0):
    """90 x 170. `screen` is SVG in a 76 x 138 box whose origin is the screen's top-left."""
    b = (rect(0, 0, 90, 170, fill="#343a40", r=15)
         + rect(7, 16, 76, 138, fill="#ffffff", r=6, sw=2)
         + line(36, 8, 54, 8, stroke="#adb5bd", sw=3)
         + f'<g transform="translate(7 16)">{screen}</g>')
    return grp(b, x, y, s, rot, opacity=opacity)


def laptop(x, y, s=1.0, screen=""):
    """180 x 118. `screen` is SVG in a 144 x 84 box, origin at the screen's top-left."""
    b = (rect(10, 0, 160, 100, fill="#495057", r=9)
         + rect(18, 8, 144, 84, fill="#ffffff", r=3, sw=2)
         + f'<g transform="translate(18 8)">{screen}</g>'
         + path("M0 102 H180 L170 117 H10 Z", fill="#ced4da"))
    return grp(b, x, y, s)


def hwkey(x, y, s=1.0):
    """USB-key-like fob. 110 x 44."""
    b = (rect(0, 10, 36, 24, fill="#ced4da", r=3)
         + rect(6, 17, 6, 10, fill="#868e96", stroke="#868e96", sw=1)
         + rect(24, 2, 82, 40, fill="#74c0fc", r=14)
         + circle(66, 22, 11, fill="#ffffff", sw=2.5)
         + circle(92, 22, 5, fill="#ffffff", sw=2.5))
    return grp(b, x, y, s)


def envelope(x, y, s=1.0, with_key=True):
    """The recovery package: cream envelope with a small gold key. 110 x 76."""
    b = (rect(0, 0, 110, 76, fill=CREAM, r=6)
         + path("M0 0 L55 42 L110 0", stroke=OUT, sw=SW, join="round"))
    if with_key:
        b += key("gold", 30, 56, 0.55)
    return grp(b, x, y, s)


def safe(x, y, s=1.0, open_door=True):
    """A small safe. 130 x 124. Interior is the area (16,16)-(114,104)."""
    b = rect(0, 0, 130, 118, fill="#adb5bd", r=10) + rect(-0, 118, 130, 6, fill="#868e96", r=3)
    if open_door:
        b += rect(14, 14, 102, 90, fill="#495057", r=5)
    else:
        b += (rect(14, 14, 102, 90, fill="#ced4da", r=5) + circle(65, 59, 24, fill="#dee2e6")
              + line(65, 59, 65, 42, sw=4))
    return grp(b, x, y, s)


def safe_door(x, y, s=1.0, right=False):
    """The swung-open door with a dial and a handle, drawn beside the safe."""
    b = (poly([(0, 14), (-44, -2), (-44, 120), (0, 104)], fill="#ced4da")
         + ellipse(-22, 59, 12, 17, fill="#ffffff", sw=2.5)
         + ellipse(-22, 59, 4, 6, fill=OUT, stroke=OUT, sw=1)
         + line(-22, 59, -22, 45, sw=3)
         + line(-33, 86, -11, 92, sw=7))
    return grp(b, x, y, s, flip=right)


def calendar(x, y, s=1.0, days=30, crossed=0, bells=(), head="30 days", big=None, fresh=False):
    """Wall calendar page, 300 x 285. 6 x 5 grid = 30 cells. Cell i (1-based) has an
    amber highlight and a bell if i is in `bells` (a dict {cell: tag text} or set)."""
    b = rect(0, 0, 300, 285, fill="#ffffff", r=12)
    b += rect(0, 0, 300, 56, fill=RED_F, r=12, stroke=OUT)
    b += rect(0, 40, 300, 16, fill=RED_F, r=0, stroke="none", sw=0) + line(0, 56, 300, 56, sw=3)
    b += circle(66, 8, 7, fill="#ffffff", sw=3) + circle(234, 8, 7, fill="#ffffff", sw=3)
    if head:
        b += text(150, 42, head, 32)
    cw, ch = 48, 40
    gx, gy = 6, 66
    over = ""
    for i in range(30):
        cx, cy = gx + (i % 6) * cw, gy + (i // 6) * (ch + 2)
        n = i + 1
        hot = n in bells
        fill = AMBER_F if hot else "#ffffff"
        b += rect(cx + 2, cy + 2, cw - 4, ch - 2, fill=fill, r=5, stroke=AMBER_S if hot else GREY_S, sw=2.5 if hot else 2)
        if n <= crossed:
            b += line(cx + 9, cy + 9, cx + cw - 9, cy + ch - 7, stroke=GREY_S, sw=4)
            b += line(cx + cw - 9, cy + 9, cx + 9, cy + ch - 7, stroke=GREY_S, sw=4)
        if hot and isinstance(bells, dict):
            over += text(cx + 2, cy + ch / 2 + 11, bells[n], 30, anchor="start")
            over += bell(cx + cw - 1, cy + 9, 0.46)
    b += over
    if big:
        b += rect(50, 100, 200, 140, fill="#ffffff", r=16, stroke=BLUE_S)
        b += text(150, 210, big, 110, fill=BLUE_S)
    return grp(b, x, y, s)


# ---------------------------------------------------------------- machine
def machine(x, y, s=1.0, state="running", vault="locked", key_hang=True, opacity=1.0, ghost_key=False, boxes=()):
    """THE MACHINE: a tall, narrow server tower (120 x 300) with four rack-style slots, status
    lights and a small square safe door on the front. y=None stands it on the floor.
    `boxes` hangs padlocked passkey boxes on its left side.
    state: running | new (dashed, dim).  vault: open (green padlock) | locked (red padlock) | none. The door itself is always shut.
    The gold unlock key hangs on a peg beside the vault (right of the body)."""
    if y is None:
        y = FLOOR - 300 * s
    new = state == "new"
    stroke = GREY_S if new else OUT
    b = rect(0, 0, 120, 300, fill="#ffffff" if new else GREY_F, r=12, stroke=stroke, dash="11 8" if new else None)
    for i in range(4):  # rack slots
        yy = 16 + 32 * i
        if new:
            b += rect(12, yy, 96, 26, fill="#ffffff", r=6, stroke=GREY_S, sw=2.5, dash="6 5")
            b += circle(27, yy + 13, 5.5, fill="#ffffff", stroke=GREY_S, sw=2.5)
        else:
            b += rect(12, yy, 96, 26, fill="#dee2e6", r=6, sw=2.5)
            b += circle(27, yy + 13, 6, fill="#51cf66" if i != 2 else "#ffd43b", sw=2.5)
            b += line(44, yy + 9, 98, yy + 9, sw=2.5, stroke=GREY_S) + line(44, yy + 18, 98, yy + 18, sw=2.5, stroke=GREY_S)
    if new:
        b += rect(16, 166, 88, 88, fill="none", r=10, stroke=GREY_S, dash="9 7")
    elif vault != "none":
        # small square safe door, always shut; its padlock icon shows the vault state
        b += rect(16, 166, 88, 88, fill="#adb5bd", r=10)
        b += rect(23, 173, 74, 74, fill="#ced4da", r=7, sw=2.5)
        for bx, by in ((31, 181), (89, 181), (31, 239), (89, 239)):
            b += circle(bx, by, 3.6, fill="#868e96", sw=2)
        b += rect(29, 197, 7, 28, fill="#868e96", r=3, sw=2.5)  # straight handle
        b += grp(vault_lock(0, 0, "open" if vault == "open" else "closed"), 63, 210, 1 / s)
    for k in range(3):  # vents
        b += line(30, 268 + k * 9, 90, 268 + k * 9, sw=3, stroke=stroke)
    b += rect(10, 298, 22, 8, fill=stroke, r=2, stroke=stroke, sw=1) + rect(88, 298, 22, 8, fill=stroke, r=2, stroke=stroke, sw=1)
    if boxes:
        b += rect(-8, 96, 14, 176, fill="#adb5bd", r=3)
        for i, st in enumerate(boxes):
            b += keybox(-116, 104 + 86 * i, 0.75, st)
    if key_hang:
        b += rect(120, 196, 28, 12, fill="#adb5bd", r=3)
        b += circle(152, 202, 7, fill="#868e96", sw=2.5)
        b += key("gold", 152, 202, 0.9, rot=90, ghost=ghost_key)
    return grp(b, x, y, s, opacity=opacity)


# ------------------------------------------------------------------ admin
def admin(x, y, s=1.0, L=(-52, 92), R=(52, 92), sit=False, flip=False, thumb=None, point=None, legs=True, chair=True):
    """THE ADMIN. Origin = base of the neck. Round head, hair, smile, orange shirt, dark trousers.
    L and R are hand positions (screen-left and screen-right, before any flip)."""
    b = ""
    if sit and chair:
        b += (rect(-50, 20, 14, 110, fill="#adb5bd", r=5) + rect(-50, 116, 140, 14, fill="#adb5bd", r=5)
              + line(-36, 130, -36, 172, sw=5) + line(80, 130, 80, 172, sw=5))
    if legs:
        if sit:
            b += (rect(-26, 86, 100, 28, fill=TROUSERS, r=12) + rect(46, 98, 28, 72, fill=TROUSERS, r=10)
                  + ellipse(64, 172, 26, 9, fill="#212529"))
        else:
            b += (rect(-29, 88, 27, 82, fill=TROUSERS, r=10) + rect(2, 88, 27, 82, fill=TROUSERS, r=10)
                  + ellipse(-17, 172, 22, 9, fill="#212529") + ellipse(17, 172, 22, 9, fill="#212529"))
    # torso
    b += rect(-36, 0, 72, 102, fill=SHIRT, r=22)
    b += path("M-12 0 L0 16 L12 0", stroke=OUT, sw=3) + rect(-36, 92, 72, 10, fill="#e8590c", r=3, sw=2.5)
    # neck + head
    b += rect(-9, -12, 18, 16, fill=SKIN, r=3, sw=2.5)
    b += circle(-28, -34, 6, fill=SKIN, sw=2.5) + circle(28, -34, 6, fill=SKIN, sw=2.5)
    b += circle(0, -43, 31, fill=HAIR)
    b += circle(0, -35, 28, fill=SKIN)
    b += path("M-27 -44 Q-14 -58 4 -52 Q18 -50 27 -42", fill=HAIR, stroke=HAIR, sw=6)
    b += circle(-10, -36, 3.8, fill=OUT, stroke=OUT, sw=1) + circle(10, -36, 3.8, fill=OUT, stroke=OUT, sw=1)
    b += path("M-11 -25 Q0 -14 11 -25", stroke=OUT, sw=3.2)
    b += circle(-18, -27, 4.5, fill="#ffa8a8", stroke="none", sw=0) + circle(18, -27, 4.5, fill="#ffa8a8", stroke="none", sw=0)
    # arms
    for side, hand in ((-1, L), (1, R)):
        sx, sy = side * 32, 16
        hx, hy = hand
        mx, my = (sx + hx) / 2, (sy + hy) / 2
        ex, ey = mx + side * 14, my + 12
        d = f"M{sx} {sy} L{ex:g} {ey:g} L{hx:g} {hy:g}"
        b += path(d, stroke=OUT, sw=23) + path(d, stroke=SHIRT, sw=16.5)
        if thumb == ("L" if side < 0 else "R"):
            b += rect(hx - 4, hy - 30, 9, 24, fill=SKIN, r=4.5, sw=2.5)
        if point and point[0] == ("L" if side < 0 else "R"):
            a = math.radians(point[1])
            fx, fy = hx + 30 * math.cos(a), hy + 30 * math.sin(a)
            b += path(f"M{hx:g} {hy:g} L{fx:g} {fy:g}", stroke=OUT, sw=13) + path(f"M{hx:g} {hy:g} L{fx:g} {fy:g}", stroke=SKIN, sw=7)
        b += circle(hx, hy, 11, fill=SKIN, sw=3)
    return grp(b, x, y, s, flip=flip)


def hand(x, y, s=1.0):
    return circle(x, y, 11 * s, fill=SKIN, sw=3)


def mug(x, y, s=1.0):
    b = (path("M30 8 q16 0 16 14 q0 12 -16 12", stroke=OUT, sw=5)
         + rect(0, 0, 34, 42, fill="#ffffff", r=6)
         + path("M10 -8 q-6 -8 0 -16 M22 -8 q-6 -8 0 -16", stroke=GREY_S, sw=3))
    return grp(b, x, y, s)


# ------------------------------------------------------- scene assembly
def badge(n):
    return circle(54, 54, 26, fill=OUT, stroke=OUT) + text(54, 65, str(n), 32, fill="#ffffff")


def floor():
    return line(40, FLOOR + 4, 1160, FLOOR + 4, stroke="#ced4da", sw=5)


def desk(x, w, top=430):
    return (rect(x, top, w, 18, fill="#dee2e6", r=4)
            + rect(x + 18, top + 18, 14, FLOOR + 4 - top - 18, fill="#adb5bd", r=2)
            + rect(x + w - 32, top + 18, 14, FLOOR + 4 - top - 18, fill="#adb5bd", r=2))


def scene(title, desc, body, badge_n=None):
    head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 620" width="1200" height="620" '
            f'font-family="{FONT}" role="img">\n<title>{escape(title)}</title>\n<desc>{escape(desc)}</desc>\n')
    bg = rect(8, 8, 1184, 604, fill=PANEL, r=34, stroke="#adb5bd", sw=3)
    return head + bg + floor() + (badge(badge_n) if badge_n else "") + body + "\n</svg>\n"


# ===================================================================== scenes
def scene_00():
    b = ""
    b += machine(190, None, 1.15, "running", "open", boxes=["okA", "okB"])
    b += label(290, 80, ["Opens the vault", "so the platform can run"], fill=GREEN_F)
    # three small apps that run, each receiving a small sealed secret ticket from the machine
    b += arrow([(334, 250), (388, 250)], color=OUT, sw=5, head=14)
    for i in range(3):
        gx = 395 + 62 * i
        b += rect(gx, 225, 52, 52, fill=BLUE_F, r=10) + gear(gx + 26, 251, 18, 8, fill="#ffffff", spin=i * 12)
        b += ticket(gx + 8, 188, 0.36)
    b += label(478, 470, "Unlock key", fill=AMBER_F)
    b += line(585, 70, 585, 560, stroke="#adb5bd", sw=3, dash="4 12")
    # admin side: phone with a fingerprint confirmation
    sc = 1.5
    scr = circle(38, 62, 29, fill=PASSKEY_F) + fingerprint(38, 64, 18) + tick(58, 108, 14)
    b += phone(680, 225, sc, scr)
    b += passkey_badge(812, 238)
    b += label(900, 80, ["Only you, with your passkey:", "full control"], fill=BLUE_F)
    b += vault_lock(640, 585, "open") + text(670, 595, "Vault open", 26, anchor="start", weight="normal")
    b += vault_lock(880, 585, "closed") + text(910, 595, "Vault closed", 26, anchor="start", weight="normal")
    b += admin(960, 331, 1.2, L=(-85, 62), R=(62, 57))
    b += ellipse(795, 378, 12, 28, fill=SKIN, sw=3).replace('<ellipse', '<ellipse transform="rotate(50 795 378)"')
    b += hand(960 - 85 * 1.2, 331 + 62 * 1.2, 1.2)
    b += envelope(1045, 385, 0.85)
    b += hand(960 + 62 * 1.2, 331 + 57 * 1.2, 1.2)
    return scene(
        "The idea: the machine opens the vault, only you with your passkey take full control",
        "On the left, a running machine with a small square safe door in its lower front, shut, and a green open padlock on it. The label says Opens the vault so the platform can run. "
        "Three small app gears, each with a small green secret ticket above it, receive from the machine and run. The big gold "
        "round-headed key hangs beside the vault, labelled Unlock key. Two small padlocked copies hang on the machine, each with a "
        "teal square-headed key, a small gold key and a passkey badge. On the right, the label says Only you, with your passkey: "
        "full control. A tiny legend at the bottom shows a green open padlock, Vault open, and a red closed padlock, Vault closed. The admin confirms on a phone with a fingerprint; the phone carries a matching passkey badge. The admin "
        "also holds a cream envelope with a small gold key, the recovery package.",
        b)


def scene_01():
    b = ""
    b += admin(215, 331, 1.2, L=(-62, 40), R=(60, 82), legs=True)
    b += desk(60, 480, 430)
    scr = (rect(8, 10, 90, 12, fill="#e9ecef", r=4, sw=0, stroke="none")
           + rect(8, 30, 128, 12, fill="#e9ecef", r=4, sw=0, stroke="none")
           + rect(8, 52, 128, 22, fill="#ffffff", r=6, sw=2.5, stroke=GREY_S)
           + rect(11, 55, 80, 16, fill="#74c0fc", r=4, sw=0, stroke="none"))
    b += laptop(290, 265, 1.4, scr)
    b += label(410, 205, "Installer", fill=BLUE_F)
    # file out of the laptop, held up in the admin's other hand
    b += file_locked(62, 262, 1.0)
    b += hand(215 - 62 * 1.2, 331 + 40 * 1.2, 1.2)
    b += label(135, 188, ["Checkpoint", "backup +", "passphrase"], fill=AMBER_F)
    # cable and progress bar
    b += path("M542 418 L700 418", stroke="#868e96", sw=6, dash="14 9")
    b += path("M700 418 L886 418", stroke="#868e96", sw=6, dash="14 9")
    b += rect(590, 330, 220, 40, fill="#ffffff", r=12)
    b += rect(596, 336, 128, 28, fill="#51cf66", r=8, sw=0, stroke="none")
    b += arrow([(610, 400), (800, 400)], color="#868e96", sw=4, head=12)
    # empty machine
    b += machine(890, None, 1.15, "new", "none", key_hang=False)
    b += label(980, 584, "Empty machine", fill="#ffffff", dash="9 6")
    return scene(
        "Step 1: the admin installs from a laptop",
        "The admin stands behind a desk with a laptop labelled Installer. A dashed cable with a half-full progress bar runs from "
        "the laptop to a new, empty machine drawn with a dashed outline and dim lights. The admin holds up a padlocked file "
        "labelled Checkpoint backup plus passphrase.",
        b, 1)


def scene_02():
    b = ""
    b += machine(660, None, 1.5, "running", "open", key_hang=True)
    # before and after: starts closed, opens itself
    b += vault_lock(150, 130, "closed")
    b += arrow([(195, 130), (335, 130)], color=OUT, sw=5, head=16)
    b += label(265, 82, "starts closed", fill="#ffffff")
    b += vault_lock(385, 130, "open")
    b += label(535, 130, "opens itself", fill=GREEN_F)
    b += admin(290, 331, 1.2, L=(-52, 90), R=(78, 30), sit=True, thumb="R")
    b += label(360, 235, "Nothing to do", fill=GREEN_F)
    return scene(
        "Step 2: the machine unlocks itself",
        "A running machine with its lights on has a small square safe door, shut, with a green open padlock on it. The gold "
        "round-headed key hangs beside the vault. At the top left, a before and after strip shows a red closed padlock, an "
        "arrow labelled starts closed, and a green open padlock labelled opens itself. The admin sits in a chair, relaxed, with a "
        "thumb up. The label says Nothing to do. There are no teal keys on the machine.",
        b, 2)


def scene_03():
    b = ""
    b += admin(200, 331, 1.2, L=(-52, 92), R=(75, 40), point=("R", -20))
    # phone: first passkey (badge A)
    b += phone(370, 150, 1.0)
    b += passkey_badge(462, 162) + tick(380, 162, 18)
    # laptop on a small table: second passkey (badge B), plain enrolment screen
    tk = grp(path("M-6 0 L-2 5 L6 -5", stroke=GREEN_S, sw=4), 0, 0)
    scr = (circle(22, 22, 12, fill="#ffffff", sw=2.5) + grp(tk, 22, 22)
           + rect(44, 15, 86, 14, fill="#e9ecef", r=4, stroke="none", sw=0)
           + circle(22, 58, 12, fill="#ffffff", sw=2.5) + grp(tk, 22, 58)
           + rect(44, 51, 66, 14, fill="#e9ecef", r=4, stroke="none", sw=0))
    b += rect(335, 500, 240, 16, fill="#dee2e6", r=4) + rect(360, 516, 12, 33, fill="#adb5bd") + rect(538, 516, 12, 33, fill="#adb5bd")
    b += laptop(365, 500 - 118 * 1.1, 1.1, scr)
    b += passkey_badge(540, 392, kind="B") + tick(372, 392, 18)
    b += machine(780, None, 1.2, "running", "open", boxes=["okA", "okB"])
    b += arrow([(476, 250), (630, 345)], color=OUT, sw=5, head=15)
    b += arrow([(560, 450), (630, 455)], color=OUT, sw=5, head=15)
    b += label(300, 584, "2 passkeys", fill=PASSKEY_F)
    return scene(
        "Step 3: the admin enrols two passkeys",
        "The admin points at two devices. The phone, the first passkey, carries badge A with a fingerprint and a green tick. "
        "A laptop on a small table, the second passkey as a backup, carries badge B with three PIN dots and a green tick; its "
        "screen shows a plain enrolment checklist with two ticks. An arrow from each device leads to the machine on the right, "
        "where two small padlocked copies hang, one per passkey, with the matching badges, each holding a teal square-headed key "
        "and a small gold key. The label says 2 passkeys. The devices carry no padlocked box.",
        b, 3)


def scene_04():
    b = ""
    b += machine(800, None, 1.15, "running", "open", key_hang=True, opacity=0.55, boxes=["okA", "okB"])
    b += admin(360, 331, 1.2, L=(-80, 55), R=(52, 92))
    b += safe(90, 340, 1.5, open_door=True)
    b += safe_door(90, 340, 1.5)
    b += envelope(155, 392, 0.9)
    b += hand(360 - 80 * 1.2, 331 + 55 * 1.2, 1.2)
    b += label(195, 292, "You keep it", fill=AMBER_F)
    return scene(
        "Step 4: the admin keeps the recovery package",
        "The admin puts a cream envelope with a small gold key on it, the recovery package, into a small safe whose door stands "
        "open and shows a dial and a handle. The label says You keep it. In the background, faded, the machine stands with its "
        "a green open padlock on its safe door and two padlocked copies on its left side.",
        b, 4)


def scene_05():
    b = ""
    b += admin(130, 349, 1.1, L=(-50, 95), R=(88, 52))
    s = 1.5
    f = 26 / s
    scr = (text(38, 40 / s, "Approve", f) + text(38, 72 / s, "this", f) + text(38, 104 / s, "change?", f)
           + circle(38, 108, 20, fill=PASSKEY_F) + fingerprint(38, 109, 12) + tick(58, 90, 11))
    b += phone(238, 238, s, scr)
    b += label(125, 132, ["1 Sign in", "as admin"], fill="#ffffff")
    b += label(335, 172, ["2 Approve", "with passkey"], fill="#ffffff")
    b += hand(130 + 88 * 1.1, 349 + 52 * 1.1, 1.1)
    b += ellipse(238 + (7 + 38) * s + 14, 238 + (16 + 108) * s + 50, 12, 24, fill=SKIN, sw=3)
    # laptop with QR
    b += desk(400, 250, 430)
    b += laptop(425, 430 - 118 * 1.2, 1.2, qr(37, 6, 72, 5))
    b += label(525, 495, ["scan to", "approve"], fill="#ffffff")
    # machine side: open vault, executor gear, tickets
    b += machine(1040, None, 0.75, "running", "open", key_hang=False)
    b += line(970, 445, 1040, 445, sw=7, stroke="#868e96")
    b += gear(930, 440, 44, 8, fill="#ced4da")
    b += arrow([(930, 394), (930, 318)], color=OUT, sw=5, head=16)
    b += curve_arrow((378, 262), (640, 60), (898, 412), color="#0ca678", sw=6, head=18)
    b += label(640, 125, ["only for", "this change"], fill="#c3fae8", stroke="#0ca678")
    b += ticket(880, 258, 0.9)
    b += label(905, 190, ["Narrow token:", "one change"], fill=GREEN_F)
    b += arrow([(980, 285), (1036, 285)], color=OUT, sw=5, head=14, dash="10 7")
    b += ticket(1045, 258, 0.9, used=True)
    b += label(1100, 205, "Used up", fill="#ffffff", dash="9 6")
    b += ticket(800, 425, 0.8, used=True)
    b += label(780, 525, ["Root token:", "used once, gone"], fill=RED_F, stroke=RED_S)
    return scene(
        "Step 5: a root token for one planned change",
        "Two step tags read left to right: 1 Sign in as admin, in the upper left, and 2 Approve with passkey, above the phone. The admin holds a phone whose screen asks Approve this change, with a fingerprint and a green tick, and touches it with a "
        "thumb. The phone shows no ticket and has no box. Next to it a laptop on a desk shows a QR code, labelled scan to "
        "approve. A teal arrow arcs from the phone, clear above the laptop, to a small gear, the executor, on the machine side, "
        "labelled only for this change. The machine's safe door carries a green open padlock. At the gear, a small root token ticket is crossed out "
        "at once, labelled Root token: used once, gone. The gear makes one green short-lived ticket with a clock, labelled "
        "Narrow token: one change, and a second, faded ticket is crossed out, labelled Used up.",
        b, 5)


def scene_06():
    b = ""
    b += label(600, 62, "Most days: nothing to do", fill=GREEN_F)
    b += admin(220, 331, 1.2, L=(-52, 90), R=(78, 80), sit=True)
    b += mug(220 + 78 * 1.2 - 8, 331 + 80 * 1.2 - 58, 1.0)
    b += hand(220 + 78 * 1.2, 331 + 80 * 1.2, 1.2)
    b += machine(560, None, 1.2, "running", "open", key_hang=True, boxes=["okA", "okB"])
    b += circ_arrow(560 + 60 * 1.2, 185 + 212 * 1.2 - 8, 70, 150, 480, color=BLUE_S, sw=6)
    # running apps
    for i, (gx, gy) in enumerate(((632 - 80, 140), (632, 130), (632 + 80, 140))):
        b += rect(gx - 32, gy - 32, 64, 64, fill=BLUE_F, r=12) + gear(gx, gy, 22, 8, fill="#ffffff", spin=i * 12)
    b += label(650, 584, "Restart: opens itself", fill=BLUE_F)
    b += calendar(900, 150, 0.8, crossed=9, bells={}, head="30 days")
    return scene(
        "Step 6: a normal day",
        "The admin sits relaxed in a chair with a drink. The machine hums with its lights on and three small gear icons above it "
        "for running apps. Its safe door carries a green open padlock, with a circular arrow around it and the label Restart: opens itself. A wall "
        "calendar on the right shows 30 days with the first days crossed off, far from the end. The banner says Most days: "
        "nothing to do.",
        b, 6)


def scene_07():
    b = ""
    # snapshot with its stored padlocked box
    b += rect(36, 215, 290, 240, fill="#ffffff", r=22, stroke=GREY_S, dash="10 8")
    b += camera(52, 250, 1.2)
    b += keybox(185, 262, 0.8, "okA")
    b += label(181, 410, "Snapshot", fill=BLUE_F)
    b += arrow([(328, 330), (408, 330)], color=OUT, sw=6, head=18)
    b += machine(420, None, 1.2, "running", "locked", key_hang=True, ghost_key=True)
    b += label(510, 584, "Vault closed", fill=RED_F, stroke=RED_S)
    b += vault_lock(688, 300, "closed") + arrow([(722, 300), (768, 300)], color=OUT, sw=4, head=13) + vault_lock(802, 300, "open")
    b += label(745, 352, "Vault open", fill=GREEN_F)
    # phone with passkey confirmation
    s = 1.5
    f = 26 / s
    scr = text(38, 30, "Restore", f * 0.98) + circle(38, 84, 27, fill=PASSKEY_F) + fingerprint(38, 86, 17) + tick(62, 62, 13)
    b += phone(850, 200, s, scr)
    b += passkey_badge(980, 214)
    b += admin(1100, 349, 1.1, L=(-62, 52), R=(40, 95), point=("L", -170))
    b += hand(1100 - 62 * 1.1, 349 + 52 * 1.1, 1.1)
    # the encrypted copy goes to the phone; the phone's approval brings the gold key back to the machine
    b += curve_arrow((250, 252), (520, 70), (870, 196), color=GREY_S, sw=4, dash="9 7", head=14)
    b += label(540, 98, "opened on the phone", size=28, fill="#ffffff", stroke=GREY_S)
    b += arrow([(842, 420), (665, 440)], color=OUT, sw=5, head=15)
    # side panel: no passkey
    b += rect(740, 30, 420, 130, fill="#ffffff", r=22, stroke=GREY_S, dash="10 8")
    b += envelope(760, 62, 0.85)
    b += text(880, 92, "No passkey?", 28, anchor="start") + text(880, 128, "Use the package", 28, anchor="start")
    return scene(
        "Step 7: restore from a snapshot",
        "A dashed frame holds a camera icon, the snapshot, and a small padlocked box with a teal square-headed key and a passkey "
        "badge stored beside it. An arrow leads to a machine whose safe door carries a red closed padlock, labelled Vault closed; a small pair shows a red closed padlock, an arrow and a green open padlock labelled Vault open. The admin confirms Restore with a "
        "fingerprint on a phone that carries a passkey badge. A dashed arrow carries the encrypted copy from the box to the phone. "
        "Another arrow leads from the phone to the machine, where a dashed gold round-headed key appears beside the vault. "
        "A dashed side panel shows the cream envelope with the words No passkey, use the package.",
        b, 7)

def scene_08():
    b = ""
    b += calendar(30, 150, 1.0, crossed=15, bells={16: "14", 23: "7", 27: "3", 29: "1"}, head="30 days")
    b += arrow([(345, 290), (420, 290)], color=OUT, sw=6, head=18)
    b += calendar(430, 150, 1.0, crossed=0, bells={}, head="", big="30")
    b += tick(715, 150, 34)
    b += phone(790, 250, 1.3, tick(38, 70, 30))
    b += admin(1050, 349, 1.1, L=(-95, 62), R=(52, 92), point=("L", -170))
    b += hand(1050 - 95 * 1.1, 349 + 62 * 1.1, 1.1)
    # corner note: machine keeps running
    b += rect(770, 18, 405, 190, fill="#ffffff", r=22, stroke=GREY_S, dash="10 8")
    b += machine(1070, 30, 0.55, "running", "none", key_hang=False)
    b += vault_lock(1040, 178, "open")
    b += text(795, 100, "If you miss it:", 28, anchor="start") + text(795, 136, "keeps running", 28, anchor="start")
    return scene(
        "Step 8: the 30-day check-in",
        "A big wall calendar shows 30 days, with small bells on the warning days 14, 7, 3 and 1. An arrow leads to a fresh "
        "calendar page marked 30, with a big green tick. The admin taps a phone that shows a tick. In a dashed corner note, a "
        "small server machine with its lights on sits beside the words If you miss it: keeps running.",
        b, 8)


def scene_09():
    b = ""
    b += admin(160, 349, 1.1, L=(-50, 95), R=(70, 20))
    b += laptop(232, 292, 0.85)
    b += passkey_badge(380, 292, kind="B")
    b += hand(160 + 70 * 1.1, 349 + 20 * 1.1, 1.1)
    # lost phone
    b += phone(250, 55, 1.0, "", opacity=0.45, rot=15)
    b += passkey_badge(335, 90, dead=True, kind="A")
    b += cross(310, 175, 28)
    b += label(455, 232, "Lost", fill=RED_F, stroke=RED_S)
    # machine: lost passkey's box removed, retained one refreshed
    b += machine(600, None, 1.2, "running", "open", key_hang=True, boxes=["deadA", "okB"])
    b += circ_arrow(425, 450, 26, 200, 520)
    b += circ_arrow(832, 345, 26, 200, 520)
    # envelope replaced
    b += envelope(880, 395, 0.85)
    b += cross(930, 425, 16)
    b += circ_arrow(1015, 425, 26, 200, 520)
    b += envelope(1050, 390, 0.95)
    b += label(1010, 512, "Replaced", fill=GREEN_F)
    return scene(
        "Step 9: a lost device is replaced",
        "The admin holds a laptop with badge B, three PIN dots. A phone, faded and tilted, has a red cross and the label Lost. "
        "On the machine, two padlocked boxes hang: the box for the lost phone's passkey is greyed, cracked and crossed out; the "
        "other box is kept and has a circular arrow beside it. A circular arrow beside the gold key at the vault shows it is "
        "renewed. On the right, an old cream envelope with a gold key is crossed out, with a circular arrow to a new "
        "envelope. The label says Replaced.",
        b, 9)

SCENES = [
    ("00-idea", scene_00), ("01-install", scene_01), ("02-first-unlock", scene_02),
    ("03-enrol", scene_03), ("04-package", scene_04), ("05-root-token", scene_05),
    ("06-normal-day", scene_06), ("07-restore", scene_07), ("08-check-in", scene_08),
    ("09-lost-device", scene_09),
]

if __name__ == "__main__":
    for name, fn in SCENES:
        with open(f"{name}.svg", "w", encoding="utf-8") as fh:
            fh.write(fn())
        print("wrote", name + ".svg")
