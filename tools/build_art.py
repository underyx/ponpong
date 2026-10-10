#!/usr/bin/env python3
"""Writes every SVG the game draws from: the app icon, the HUD icons, one
art window per card and one emblem per opponent, into assets/. Godot imports
SVG natively (ThorVG), so nothing is rasterised here; keep to the shapes it
renders (paths, circles, rects, groups, gradients, dashes; no <text>, no
<pattern>, no filters).

The card table is read from scripts/card_library.gd and the roster from
scripts/opponent_library.gd, so the art follows the data: rerun this after
changing either. The palette mirrors scripts/ui/palette.gd; change both.

    python3 tools/build_art.py          # from the project root
"""
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INK = "#1a1830"
INK_SOFT = "#2b2846"
PAPER = "#f5eedc"
PAPER_BRIGHT = "#fff9ea"
ORANGE = "#ff7a2e"
YELLOW = "#ffc83d"
BLUE = "#2f6eb8"
BLUE_DEEP = "#214f8a"
BLUE_LIGHT = "#7db7f0"
TEAL = "#1fae8a"
PINK = "#f0486e"
VIOLET = "#5a3f8e"
WOOD = "#c98b55"
WOOD_DARK = "#8c5a33"

BALL_TYPES = {"NONE": 0, "FLAT": 1, "HIGH": 2, "SPIN": 3, "FAST": 4}


# --- helpers ----------------------------------------------------------------------

def write(path, svg):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", newline="\n") as f:
        f.write(svg)
    print("wrote", path)


def svg(width, height, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n%s</svg>\n'
            % (width, height, width, height, body))


def fmt(v):
    return ("%.1f" % v).rstrip("0").rstrip(".")


def quad(p0, c, p1, t):
    """A point on the quadratic bezier p0, c, p1."""
    x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0]
    y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]
    return x, y


def quad_tangent(p0, c, p1, t):
    dx = 2 * (1 - t) * (c[0] - p0[0]) + 2 * t * (p1[0] - c[0])
    dy = 2 * (1 - t) * (c[1] - p0[1]) + 2 * t * (p1[1] - c[1])
    n = math.hypot(dx, dy) or 1.0
    return dx / n, dy / n


def halftone(x0, y0, x1, y1, step, color, alpha, grow="x"):
    """A grid of dots that grow along `grow` (x, y or xy): the print thinning out."""
    out = []
    cols = int((x1 - x0) / step)
    rows = int((y1 - y0) / step)
    for j in range(rows + 1):
        for i in range(cols + 1):
            fx = i / max(cols, 1)
            fy = j / max(rows, 1)
            f = {"x": fx, "y": fy, "xy": (fx + fy) / 2, "-x": 1 - fx, "-y": 1 - fy}[grow]
            r = step * 0.46 * f
            if r < 0.6:
                continue
            x = x0 + i * step + (step / 2 if j % 2 else 0)
            y = y0 + j * step
            out.append('<circle cx="%s" cy="%s" r="%s" fill="%s" fill-opacity="%s"/>' % (fmt(x), fmt(y), fmt(r), color, alpha))
    return "\n".join(out)


def rgb_to_hex(r, g, b):
    return "#%02x%02x%02x" % (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def darken(hexcol, amount):
    r, g, b = int(hexcol[1:3], 16), int(hexcol[3:5], 16), int(hexcol[5:7], 16)
    return "#%02x%02x%02x" % (int(r * (1 - amount)), int(g * (1 - amount)), int(b * (1 - amount)))


# --- the data, read from the GDScript ----------------------------------------------

CARD_RE = re.compile(
    r'Card\.make\("(?P<id>\w+)",\s*"(?P<title>[^"]*)",\s*"(?P<flavor>(?:[^"\\]|\\.)*)",\s*'
    r'(?P<power>[\d.]+),\s*(?P<control>[\d.]+),\s*BallType\.(?P<produces>\w+),\s*'
    r'\[(?P<strong>[^\]]*)\],\s*\[(?P<weak>[^\]]*)\],\s*'
    r'Color\((?P<r>[\d.]+),\s*(?P<g>[\d.]+),\s*(?P<b>[\d.]+)\),\s*'
    r'(?P<arc>[\d.]+),\s*(?P<speed>[\d.]+)(?:,\s*(?P<row>-?\d+))?(?:,\s*(?P<cost>\d+))?'
    r'(?:,\s*Card\.Rarity\.(?P<rarity>\w+))?(?:,\s*"(?P<keyword>\w*)")?\s*\)', re.S)


def read_cards():
    src = open(os.path.join(ROOT, "scripts/card_library.gd")).read()
    cards = []
    for m in CARD_RE.finditer(src):
        d = m.groupdict()
        strong = [s.strip().split(".")[-1] for s in d["strong"].split(",") if s.strip()]
        cards.append({
            "id": d["id"], "title": d["title"],
            "power": float(d["power"]), "control": float(d["control"]),
            "produces": d["produces"], "serve": "NONE" in strong,
            "color": rgb_to_hex(float(d["r"]), float(d["g"]), float(d["b"])),
            "arc": float(d["arc"]), "speed": float(d["speed"]),
            "row": int(d["row"]) if d["row"] is not None else -1,
            "cost": int(d["cost"]) if d["cost"] is not None else 1,
            "rarity": d["rarity"] or "COMMON", "keyword": d["keyword"] or "",
        })
    return cards


OPP_RE = re.compile(r'"(?P<id>\w+)":\s*\{\s*"name":\s*"(?P<name>(?:[^"\\]|\\.)*)".*?'
                    r'"paddle_color":\s*Color\((?P<r>[\d.]+),\s*(?P<g>[\d.]+),\s*(?P<b>[\d.]+)\)', re.S)


def read_opponents():
    src = open(os.path.join(ROOT, "scripts/opponent_library.gd")).read()
    return [(m.group("id"), rgb_to_hex(float(m.group("r")), float(m.group("g")), float(m.group("b"))))
            for m in OPP_RE.finditer(src)]


# --- icons --------------------------------------------------------------------------
# Drawn in white so a TextureRect can modulate them to ink or paper.

W = "#ffffff"


def icon_ball():
    return svg(48, 48, (
        '<circle cx="24" cy="24" r="19" fill="%s"/>\n'
        '<path d="M9 18 Q24 30 39 18" fill="none" stroke="%s" stroke-opacity="0.35" stroke-width="3"/>\n'
    ) % (W, INK))


def icon_heart():
    return svg(48, 48, (
        '<path d="M24 42 C10 32 4 25 4 16 C4 9 9 5 15 5 C19 5 22 7 24 10 C26 7 29 5 33 5 C39 5 44 9 44 16 '
        'C44 25 38 32 24 42 Z" fill="%s"/>\n') % W)


def icon_bolt():
    return svg(48, 48, '<path d="M27 3 L9 27 L22 27 L19 45 L39 19 L26 19 Z" fill="%s"/>\n' % W)


def icon_type(kind):
    if kind == "flat":
        body = ('<path d="M6 24 H34" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<path d="M28 14 L40 24 L28 34" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>\n') % (W, W)
    elif kind == "high":
        body = ('<path d="M6 38 Q24 -6 42 38" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<circle cx="42" cy="38" r="5" fill="%s"/>\n') % (W, W)
    elif kind == "spin":
        body = ('<path d="M24 8 A16 16 0 1 1 9 30" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<path d="M4 24 L10 32 L17 25" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>\n'
                '<circle cx="24" cy="24" r="4" fill="%s"/>\n') % (W, W, W)
    elif kind == "fast":
        body = ('<path d="M4 14 H18 M4 24 H14 M4 34 H18" stroke="%s" stroke-width="4" stroke-linecap="round"/>\n'
                '<path d="M20 24 H36" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<path d="M30 14 L42 24 L30 34" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>\n') % (W, W, W)
    else:  # serve: a tossed ball over an open hand
        body = ('<circle cx="24" cy="12" r="7" fill="%s"/>\n'
                '<path d="M10 30 Q24 40 38 30" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<path d="M24 22 V26" stroke="%s" stroke-width="4" stroke-linecap="round" stroke-dasharray="1 5"/>\n') % (W, W, W)
    return svg(48, 48, body)


def icon_keyword(kind):
    if kind == "rest":  # a crescent moon
        body = '<path d="M30 6 A18 18 0 1 0 42 30 A13 13 0 0 1 30 6 Z" fill="%s"/>\n' % W
    elif kind == "sap":  # a drop with a minus
        body = ('<path d="M24 4 C24 4 9 22 9 30 A15 15 0 0 0 39 30 C39 22 24 4 24 4 Z" fill="%s"/>\n'
                '<path d="M17 31 H31" stroke="%s" stroke-width="4" stroke-linecap="round"/>\n') % (W, INK)
    elif kind == "exhaust":  # a flame going out
        body = ('<path d="M24 4 C30 14 36 18 36 28 A12 12 0 0 1 12 28 C12 22 16 18 18 14 C19 20 22 22 24 22 C26 18 23 10 24 4 Z" fill="%s"/>\n'
                '<path d="M8 42 H40" stroke="%s" stroke-width="4" stroke-linecap="round" stroke-dasharray="2 6"/>\n') % (W, W)
    elif kind == "steady":  # an anchor
        body = ('<circle cx="24" cy="8" r="4" fill="none" stroke="%s" stroke-width="4"/>\n'
                '<path d="M24 12 V40 M12 22 H36 M8 30 A16 16 0 0 0 40 30" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>\n') % (W, W)
    elif kind == "reach":  # a long arrow stretching out
        body = ('<path d="M6 36 L36 12" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<path d="M22 10 H38 V26" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>\n'
                '<circle cx="8" cy="38" r="5" fill="%s"/>\n') % (W, W, W)
    else:  # heavy: a kettlebell weight
        body = ('<path d="M14 18 A10 10 0 0 1 34 18" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>\n'
                '<circle cx="24" cy="30" r="14" fill="%s"/>\n') % (W, W)
    return svg(48, 48, body)


def icon_rarity(kind):
    if kind == "common":
        return svg(32, 32, '<circle cx="16" cy="16" r="9" fill="%s"/>\n' % W)
    if kind == "uncommon":
        return svg(32, 32, '<path d="M16 4 L28 16 L16 28 L4 16 Z" fill="%s"/>\n' % W)
    return svg(32, 32, '<path d="M16 3 L19.5 12 L29 12.5 L21.5 18.5 L24 28 L16 22.5 L8 28 L10.5 18.5 L3 12.5 L12.5 12 Z" fill="%s"/>\n' % W)


def icon_cursor():
    """Four corner brackets: the zone cursor, drawn over a hovered zone."""
    b = []
    for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        x0 = 24 + sx * 22
        y0 = 24 + sy * 22
        b.append('<path d="M%s %s H%s V%s" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
                 % (fmt(x0), fmt(y0 + sy * -12), fmt(x0), fmt(y0), W) if False else
                 '<path d="M%s %s L%s %s L%s %s" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
                 % (fmt(x0), fmt(y0 - sy * 12), fmt(x0), fmt(y0), fmt(x0 - sx * 12), fmt(y0), W))
    return svg(48, 48, "\n".join(b) + "\n")


def icon_paddle():
    return svg(48, 48, (
        '<g transform="rotate(-35 24 24)">'
        '<rect x="21" y="26" width="6" height="18" rx="2" fill="%s"/>'
        '<circle cx="24" cy="16" r="13" fill="%s"/>'
        '</g>\n') % (W, W))


# --- the app icon --------------------------------------------------------------------

def app_icon():
    body = []
    body.append('<defs><clipPath id="plate"><rect width="128" height="128" rx="28"/></clipPath></defs>')
    body.append('<rect width="128" height="128" rx="28" fill="%s"/>' % INK)
    body.append('<g clip-path="url(#plate)">%s</g>' % halftone(66, 66, 128, 128, 9, PAPER, "0.16", "xy"))
    # The table edge: a slab of blue with a paper rim and the net.
    body.append('<path d="M8 86 L120 86 L112 104 L16 104 Z" fill="%s" stroke="%s" stroke-width="4" stroke-linejoin="round"/>' % (BLUE, PAPER))
    body.append('<rect x="62" y="70" width="4" height="22" fill="%s"/>' % PAPER)
    # The paddle, tilted, with its rubber and a wood handle.
    body.append('<g transform="rotate(-28 44 52)">'
                '<rect x="38" y="60" width="12" height="30" rx="4" fill="%s" stroke="%s" stroke-width="3"/>'
                '<circle cx="44" cy="44" r="24" fill="%s" stroke="%s" stroke-width="4"/>'
                '<circle cx="44" cy="44" r="16" fill="none" stroke="%s" stroke-opacity="0.25" stroke-width="3"/>'
                '</g>' % (WOOD, INK, PINK, INK, INK))
    # The ball, big, with a paper seam and a highlight.
    body.append('<circle cx="92" cy="40" r="22" fill="%s" stroke="%s" stroke-width="4"/>' % (ORANGE, INK))
    body.append('<path d="M74 34 Q92 50 110 34" fill="none" stroke="%s" stroke-width="3" stroke-opacity="0.8"/>' % PAPER)
    body.append('<circle cx="84" cy="31" r="4" fill="%s"/>' % PAPER_BRIGHT)
    return svg(128, 128, "\n".join(body) + "\n")


# --- card art -------------------------------------------------------------------------

ART_W, ART_H = 272, 136
TABLE_Y = 108.0
NET_X = 136.0
NET_H = 30.0
CONTACT = (46.0, 70.0)


def card_art(card):
    produces = card["produces"]
    base = card["color"]
    deep = darken(base, 0.22)
    body = []
    body.append('<rect width="%d" height="%d" fill="%s"/>' % (ART_W, ART_H, base))
    # The print thins to halftone toward the bottom right.
    body.append(halftone(150, 30, 268, 132, 11, deep, "0.55", "xy"))
    # A spotlight on the far side where the ball is going.
    land_x = {0: 176.0, 1: 244.0}.get(card["row"], 210.0)
    body.append('<ellipse cx="%s" cy="%s" rx="34" ry="8" fill="%s" fill-opacity="0.35"/>' % (fmt(land_x), fmt(TABLE_Y + 2), PAPER))
    # The table: a thick line with a paper rim, and the net in the middle.
    body.append('<rect x="8" y="%s" width="256" height="14" rx="3" fill="%s" stroke="%s" stroke-width="3"/>'
                % (fmt(TABLE_Y), BLUE, INK))
    body.append('<rect x="%s" y="%s" width="4" height="%s" fill="%s" stroke="%s" stroke-width="2"/>'
                % (fmt(NET_X - 2), fmt(TABLE_Y - NET_H), fmt(NET_H), PAPER, INK))
    for i in range(1, 6):
        y = TABLE_Y - NET_H + i * NET_H / 6
        body.append('<path d="M%s %s H%s" stroke="%s" stroke-opacity="0.45" stroke-width="1.5"/>' % (fmt(NET_X - 8), fmt(y), fmt(NET_X + 8), INK))
    body.append('<rect x="%s" y="%s" width="20" height="4" rx="2" fill="%s" stroke="%s" stroke-width="2"/>'
                % (fmt(NET_X - 10), fmt(TABLE_Y - NET_H - 2), PAPER, INK))

    # The flight: a quadratic arc from the paddle to the landing spot, its
    # apex set by the card's arc_height (0.15 skims, 1.6 goes to the moon).
    apex_f = min(max((card["arc"] - 0.15) / (1.6 - 0.15), 0.0), 1.0)
    start = CONTACT
    if card["serve"]:
        start = (54.0, 52.0)
    end = (land_x, TABLE_Y - 4)
    apex_y = 84.0 - apex_f * 70.0
    ctrl = ((start[0] + end[0]) / 2, 2 * apex_y - (start[1] + end[1]) / 2)
    d = "M%s %s Q%s %s %s %s" % (fmt(start[0]), fmt(start[1]), fmt(ctrl[0]), fmt(ctrl[1]), fmt(end[0]), fmt(end[1]))
    dash = {"HIGH": "4 7", "SPIN": "9 5", "FAST": "16 4", "FLAT": "12 5"}.get(produces, "12 5")
    body.append('<path d="%s" fill="none" stroke="%s" stroke-width="7" stroke-linecap="round" stroke-opacity="0.35"/>' % (d, INK))
    body.append('<path d="%s" fill="none" stroke="%s" stroke-width="3.5" stroke-linecap="round" stroke-dasharray="%s"/>' % (d, PAPER, dash))
    # The bounce past the landing: a shorter hop that leaves the frame.
    hop_end = (min(end[0] + 40, 268), TABLE_Y - 30)
    hop_ctrl = (end[0] + 18, TABLE_Y - 4 - apex_f * 20 - 30)
    body.append('<path d="M%s %s Q%s %s %s %s" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-dasharray="3 6" stroke-opacity="0.7"/>'
                % (fmt(end[0]), fmt(end[1]), fmt(hop_ctrl[0]), fmt(hop_ctrl[1]), fmt(hop_end[0]), fmt(hop_end[1]), PAPER))
    # The landing ring.
    body.append('<ellipse cx="%s" cy="%s" rx="14" ry="5" fill="none" stroke="%s" stroke-width="3"/>' % (fmt(end[0]), fmt(TABLE_Y - 2), YELLOW))

    # The ball in flight, with what the shot does to it.
    t = 0.56
    bx, by = quad(start, ctrl, end, t)
    tx, ty = quad_tangent(start, ctrl, end, t)
    if produces == "FAST":
        n = 3 + int(round((card["speed"] - 0.5) * 2))
        for i in range(n):
            back = 16 + i * 9
            x0, y0 = bx - tx * back, by - ty * back
            x1, y1 = bx - tx * (back + 10 + i * 3), by - ty * (back + 10 + i * 3)
            body.append('<path d="M%s %s L%s %s" stroke="%s" stroke-width="4" stroke-linecap="round" stroke-opacity="%s"/>'
                        % (fmt(x0), fmt(y0), fmt(x1), fmt(y1), PAPER, fmt(0.9 - i * 0.18)))
    if produces == "SPIN":
        # Two curled arrows chasing the ball around.
        for sign in (1, -1):
            body.append('<path d="M%s %s A17 17 0 0 %s %s %s" fill="none" stroke="%s" stroke-width="3.5" stroke-linecap="round"/>'
                        % (fmt(bx - sign * 17), fmt(by - sign * 6), 1 if sign > 0 else 1,
                           fmt(bx + sign * 6), fmt(by + sign * 17), INK))
            hx, hy = bx + sign * 6, by + sign * 17
            body.append('<path d="M%s %s L%s %s L%s %s" fill="none" stroke="%s" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>'
                        % (fmt(hx - sign * 8), fmt(hy - sign * 1), fmt(hx), fmt(hy), fmt(hx + sign * 1), fmt(hy - sign * 9), INK))
    if produces == "HIGH":
        # A float: little air lines under the ball.
        for i in range(3):
            body.append('<path d="M%s %s H%s" stroke="%s" stroke-width="2.5" stroke-linecap="round" stroke-opacity="0.7"/>'
                        % (fmt(bx - 14 + i * 4), fmt(by + 16 + i * 5), fmt(bx + 14 - i * 4), PAPER))
    body.append('<circle cx="%s" cy="%s" r="11" fill="%s" stroke="%s" stroke-width="3"/>' % (fmt(bx), fmt(by), ORANGE, INK))
    body.append('<path d="M%s %s Q%s %s %s %s" fill="none" stroke="%s" stroke-width="2" stroke-opacity="0.8"/>'
                % (fmt(bx - 8), fmt(by - 3), fmt(bx), fmt(by + 5), fmt(bx + 8), fmt(by - 3), PAPER))
    body.append('<circle cx="%s" cy="%s" r="2.5" fill="%s"/>' % (fmt(bx - 4), fmt(by - 5), PAPER_BRIGHT))

    # The paddle at the point of contact, tilted for the stroke.
    angle = {"SPIN": 28, "HIGH": 14, "FAST": -42, "FLAT": -8}.get(produces, 0)
    if card["id"] in ("chop", "line_chop", "heavy_chop", "push"):
        angle = 44
    if card["id"] in ("smash", "flat_kill"):
        angle = -62
    px, py = (start[0] - 8, start[1] + 2)
    body.append('<g transform="rotate(%d %s %s)">'
                '<rect x="%s" y="%s" width="11" height="30" rx="4" fill="%s" stroke="%s" stroke-width="3"/>'
                '<ellipse cx="%s" cy="%s" rx="19" ry="22" fill="%s" stroke="%s" stroke-width="3.5"/>'
                '<ellipse cx="%s" cy="%s" rx="11" ry="13" fill="none" stroke="%s" stroke-opacity="0.25" stroke-width="3"/>'
                '</g>' % (angle, fmt(px), fmt(py),
                          fmt(px - 5.5), fmt(py + 16), WOOD, INK,
                          fmt(px), fmt(py), PINK, INK,
                          fmt(px), fmt(py), INK))
    # A swing streak behind the blade.
    body.append('<path d="M%s %s Q%s %s %s %s" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-opacity="0.55"/>'
                % (fmt(px - 26), fmt(py - 26 + (10 if angle > 0 else -4)), fmt(px - 30), fmt(py), fmt(px - 24), fmt(py + 24 - (10 if angle > 0 else 0)), PAPER))
    # A serve tosses the ball from a hand: a little stack of dots up to it.
    if card["serve"]:
        for i in range(3):
            body.append('<circle cx="%s" cy="%s" r="2" fill="%s" fill-opacity="0.8"/>' % (fmt(start[0] - 2), fmt(start[1] + 14 + i * 9), PAPER))

    # The keyword's mark, stamped in the top left.
    if card["keyword"]:
        body.append('<circle cx="30" cy="26" r="19" fill="%s" stroke="%s" stroke-width="3"/>' % (INK, PAPER))
        body.append('<g transform="translate(16 12) scale(0.58)">%s</g>' % icon_keyword(card["keyword"]).split("\n", 1)[1].rsplit("</svg>", 1)[0].replace(W, PAPER))
    return svg(ART_W, ART_H, "\n".join(body) + "\n")


# --- opponent emblems ------------------------------------------------------------------

def emblem(opp_id, color):
    motif = {
        "coach_pim": (
            # A whistle on a lanyard.
            '<path d="M64 22 V48" stroke="{p}" stroke-width="4" stroke-dasharray="2 5" stroke-linecap="round"/>'
            '<path d="M40 56 H86 A14 14 0 0 1 86 84 H68 L60 100 L40 84 A14 14 0 0 1 40 56 Z" fill="{p}" stroke="{i}" stroke-width="4" stroke-linejoin="round"/>'
            '<circle cx="54" cy="70" r="6" fill="{i}"/>'),
        "mara_vale": (
            # Three chops, slicing down and under.
            '<path d="M30 46 Q64 30 98 46" fill="none" stroke="{p}" stroke-width="7" stroke-linecap="round"/>'
            '<path d="M30 66 Q64 50 98 66" fill="none" stroke="{p}" stroke-width="7" stroke-linecap="round" stroke-opacity="0.75"/>'
            '<path d="M30 86 Q64 70 98 86" fill="none" stroke="{p}" stroke-width="7" stroke-linecap="round" stroke-opacity="0.5"/>'),
        "jax_dunn": (
            # A bolt.
            '<path d="M72 22 L42 68 L62 68 L54 106 L88 56 L68 56 Z" fill="{p}" stroke="{i}" stroke-width="4" stroke-linejoin="round"/>'),
        "dot_and_dash": (
            # Dot, dash, dot.
            '<circle cx="36" cy="64" r="10" fill="{p}"/>'
            '<rect x="52" y="56" width="40" height="16" rx="8" fill="{p}"/>'
            '<circle cx="104" cy="64" r="10" fill="{p}" fill-opacity="0.6"/>'
            '<circle cx="64" cy="36" r="5" fill="{p}" fill-opacity="0.6"/>'
            '<circle cx="64" cy="92" r="5" fill="{p}" fill-opacity="0.6"/>'),
        "oona_sato": (
            # A spiral.
            '<path d="M64 64 m0 -4 a4 4 0 1 1 -4 4 a10 10 0 1 0 10 -10 a18 18 0 1 1 -18 18 a26 26 0 1 0 26 -26 a34 34 0 1 1 -34 34" '
            'fill="none" stroke="{p}" stroke-width="6" stroke-linecap="round"/>'),
        "big_rig": (
            # A brick wall.
            '<g fill="{p}" stroke="{i}" stroke-width="3">'
            '<rect x="30" y="38" width="30" height="16" rx="2"/><rect x="66" y="38" width="30" height="16" rx="2"/>'
            '<rect x="22" y="60" width="26" height="16" rx="2"/><rect x="54" y="60" width="30" height="16" rx="2"/><rect x="90" y="60" width="16" height="16" rx="2"/>'
            '<rect x="30" y="82" width="30" height="16" rx="2"/><rect x="66" y="82" width="30" height="16" rx="2"/>'
            '</g>'),
        "kit_marlow": (
            # Crosshair on the sideline.
            '<circle cx="64" cy="64" r="26" fill="none" stroke="{p}" stroke-width="6"/>'
            '<path d="M64 26 V44 M64 84 V102 M26 64 H44 M84 64 H102" stroke="{p}" stroke-width="6" stroke-linecap="round"/>'
            '<circle cx="64" cy="64" r="6" fill="{p}"/>'),
        "ilse_varga": (
            # A crown.
            '<path d="M30 90 L26 46 L48 64 L64 36 L80 64 L102 46 L98 90 Z" fill="{p}" stroke="{i}" stroke-width="4" stroke-linejoin="round"/>'
            '<circle cx="26" cy="44" r="5" fill="{p}"/><circle cx="64" cy="33" r="5" fill="{p}"/><circle cx="102" cy="44" r="5" fill="{p}"/>'
            '<rect x="30" y="84" width="68" height="10" fill="{i}" fill-opacity="0.35"/>'),
        "your_shadow": (
            # A paddle and its reflection.
            '<g transform="rotate(-30 64 64)">'
            '<rect x="58" y="62" width="12" height="30" rx="4" fill="{p}"/><circle cx="64" cy="46" r="22" fill="{p}"/>'
            '</g>'
            '<g transform="rotate(150 64 64)" fill="{p}" fill-opacity="0.35">'
            '<rect x="58" y="62" width="12" height="30" rx="4"/><circle cx="64" cy="46" r="22"/>'
            '</g>'),
    }[opp_id]
    ring = INK
    body = []
    body.append('<circle cx="64" cy="64" r="60" fill="%s"/>' % ring)
    body.append('<defs><clipPath id="disc"><circle cx="64" cy="64" r="50"/></clipPath></defs>')
    body.append('<circle cx="64" cy="64" r="52" fill="%s" stroke="%s" stroke-width="4"/>' % (color, PAPER))
    body.append('<g clip-path="url(#disc)">%s</g>' % halftone(56, 56, 116, 116, 8, INK, "0.22", "xy"))
    body.append(motif.format(p=PAPER, i=INK))
    return svg(128, 128, "\n".join(body) + "\n")


# --- main ----------------------------------------------------------------------------------

def main():
    write("icon.svg", app_icon())
    write("assets/icons/ball.svg", icon_ball())
    write("assets/icons/heart.svg", icon_heart())
    write("assets/icons/bolt.svg", icon_bolt())
    write("assets/icons/cursor.svg", icon_cursor())
    write("assets/icons/paddle.svg", icon_paddle())
    for kind in ("serve", "flat", "high", "spin", "fast"):
        write("assets/icons/type_%s.svg" % kind, icon_type(kind))
    for kind in ("rest", "sap", "exhaust", "steady", "reach", "heavy"):
        write("assets/icons/kw_%s.svg" % kind, icon_keyword(kind))
    for kind in ("common", "uncommon", "rare"):
        write("assets/icons/rarity_%s.svg" % kind, icon_rarity(kind))
    cards = read_cards()
    if len(cards) < 25:
        print("only %d cards parsed from card_library.gd" % len(cards), file=sys.stderr)
        sys.exit(1)
    for card in cards:
        write("assets/cards/%s.svg" % card["id"], card_art(card))
    opponents = read_opponents()
    if len(opponents) < 9:
        print("only %d opponents parsed from opponent_library.gd" % len(opponents), file=sys.stderr)
        sys.exit(1)
    for opp_id, color in opponents:
        write("assets/opponents/%s.svg" % opp_id, emblem(opp_id, color))


if __name__ == "__main__":
    main()
