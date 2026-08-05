"""Colour, glyphs and meter drawing."""

import os

DARK = {
    "label": "EDEDED",
    "secondary": "98989D",
    "tertiary": "636366",
    "track": "3A3A3C",
    "calm": "A1A1A6",
    "yellow": "FFD60A",
    "orange": "FF9F0A",
    "red": "FF453A",
    "green": "30D158",
    "blue": "0A84FF",
    "purple": "BF5AF2",
}

LIGHT = {
    "label": "1D1D1F",
    "secondary": "6E6E73",
    "tertiary": "8E8E93",
    "track": "D2D2D7",
    "calm": "6E6E73",
    "yellow": "B25000",
    "orange": "C93400",
    "red": "D70015",
    "green": "248A3D",
    "blue": "0071E3",
    "purple": "8944AB",
}

EIGHTHS = " ▏▎▍▌▋▊▉"

_XTERM_LEVELS = (0, 95, 135, 175, 215, 255)


def _nearest_cube(v):
    best, bi = 999, 0
    for i, level in enumerate(_XTERM_LEVELS):
        d = abs(level - v)
        if d < best:
            best, bi = d, i
    return bi


def _to_256(hexcode):
    r, g, b = (int(hexcode[i : i + 2], 16) for i in (0, 2, 4))
    if abs(r - g) < 8 and abs(g - b) < 8:
        grey = 232 + min(23, max(0, (r - 8) // 10))
        return grey
    return 16 + 36 * _nearest_cube(r) + 6 * _nearest_cube(g) + _nearest_cube(b)


class Theme:
    def __init__(self, mode="dark", truecolor=None, bar_style="solid", bar_width=8):
        self.c = LIGHT if mode == "light" else DARK
        if truecolor is None:
            truecolor = os.environ.get("COLORTERM", "") in ("truecolor", "24bit")
        self.truecolor = truecolor
        self.bar_style = bar_style
        self.bar_width = bar_width

    def fg(self, key):
        h = self.c.get(key, key)
        if self.truecolor:
            r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
            return f"\033[38;2;{r};{g};{b}m"
        return f"\033[38;5;{_to_256(h)}m"

    def bg(self, key):
        h = self.c.get(key, key)
        if self.truecolor:
            r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
            return f"\033[48;2;{r};{g};{b}m"
        return f"\033[48;5;{_to_256(h)}m"

    def paint(self, text, key):
        return f"{self.fg(key)}{text}\033[0m"

    def level(self, pct):
        """Stay monochrome while things are fine; earn colour only when they aren't."""
        if pct >= 93:
            return "red"
        if pct >= 80:
            return "orange"
        if pct >= 60:
            return "yellow"
        return "calm"

    def meter(self, pct, width=None, key=None):
        width = width or self.bar_width
        key = key or self.level(pct)
        frac = max(0.0, min(1.0, pct / 100.0))

        if self.bar_style == "dots":
            n = int(round(frac * width))
            return (
                self.fg(key) + "●" * n + self.fg("track") + "●" * (width - n) + "\033[0m"
            )

        cells = frac * width
        full = int(cells)
        rem = cells - full
        step = int(rem * 8)

        if self.bar_style == "hairline":
            body = self.fg(key) + "▁" * full
            if full < width:
                body += self.fg(key) + EIGHTHS[step] if step else ""
                drawn = full + (1 if step else 0)
                body += self.fg("track") + "▁" * (width - drawn)
            return body + "\033[0m"

        out = self.fg(key) + "█" * full
        drawn = full
        if step and full < width:
            out += self.bg("track") + self.fg(key) + EIGHTHS[step] + "\033[49m"
            drawn += 1
        if drawn < width:
            out += self.fg("track") + "█" * (width - drawn)
        return out + "\033[0m"
