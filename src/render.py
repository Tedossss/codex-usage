"""Composes the status line and the expanded panel."""

import os
import re
import subprocess
import time

from data import forecast, live_sessions
from theme import Theme

ANSI = re.compile(r"\033\[[0-9;]*m")

GLYPH = {
    "reset": "↺",
    "rise": "↗",
    "stack": "⧉",
    "branch": "⎇",
    "busy": "●",
    "idle": "○",
}

# Lower number is dropped first when the terminal is narrow.
PRIORITY = {
    "five_hour": 100,
    "seven_day": 90,
    "forecast": 80,
    "context": 70,
    "model": 60,
    "sessions": 50,
    "location": 40,
    "cost": 30,
}


def visible_len(s):
    return len(ANSI.sub("", s))


def fmt_span(seconds, compact=False):
    seconds = int(max(0, seconds))
    d, rem = divmod(seconds, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    gap = "" if compact else " "
    if d:
        return f"{d}d{gap}{h}h"
    if h:
        return f"{h}h{gap}{m:02d}m"
    if m:
        return f"{m}m"
    return "<1m"


def fmt_cost(usd):
    if not usd:
        return "$0"
    if usd < 0.01:
        return f"${usd:.3f}"
    return f"${usd:.2f}"


def fmt_clock(epoch):
    fmt = "%H:%M" if epoch - time.time() < 20 * 3600 else "%a %H:%M"
    return time.strftime(fmt, time.localtime(epoch))


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(int(n))


def shorten_path(path, keep=2):
    home = os.path.expanduser("~")
    if path.startswith(home):
        path = "~" + path[len(home) :]
    parts = [p for p in path.split(os.sep) if p]
    if len(parts) <= keep:
        return path
    return "…/" + "/".join(parts[-keep:])


def git_branch(cwd):
    if not cwd or not os.path.isdir(cwd):
        return None
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "symbolic-ref", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=1.0,
        )
        if out.returncode == 0:
            return out.stdout.strip() or None
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=1.0,
        )
        return out.stdout.strip() or None
    except Exception:
        return None


def model_label(payload):
    m = payload.get("model") or {}
    name = m.get("display_name") or m.get("id") or "?"
    return re.sub(r"\s*\([^)]*\)\s*$", "", name)


def _window(payload, key):
    return ((payload.get("rate_limits") or {}).get(key)) or {}


# ---------------------------------------------------------------- status line


def build_segments(payload, cfg, theme, samples):
    now = time.time()
    seg = {}

    def add(name, styled, plain=None):
        seg[name] = {"styled": styled, "plain": plain or ANSI.sub("", styled)}

    # model
    name = model_label(payload)
    key = "blue" if payload.get("fast_mode") else "secondary"
    effort = ((payload.get("effort") or {}).get("level")) or ""
    tail = f" {effort}" if effort in ("xhigh", "max") else ""
    add("model", theme.paint(name, key) + theme.paint(tail, "tertiary"))

    # the two limit windows
    # A 7-day reset four days out is not news; only surface it once it matters.
    reset_floor = {"five_hour": cfg["show_reset_above"], "seven_day": 80}
    for name, label, index in (("five_hour", "5H", 1), ("seven_day", "7D", 2)):
        w = _window(payload, name)
        pct = w.get("used_percentage")
        if pct is None:
            continue
        lvl = theme.level(pct)
        body = (
            theme.paint(label, "tertiary")
            + " "
            + theme.meter(pct, key=lvl)
            + " "
            + theme.paint(f"{pct:.0f}%", lvl)
        )
        resets_at = w.get("resets_at")
        if resets_at and pct >= reset_floor[name]:
            body += theme.paint(
                f" {GLYPH['reset']}{fmt_span(resets_at - now, compact=True)}", "tertiary"
            )
        add(name, body)

    # pace — present only when this session is on course to exhaust a window
    worst = None
    for label, index, key_name in (("5H", 1, "five_hour"), ("7D", 2, "seven_day")):
        w = _window(payload, key_name)
        pct = w.get("used_percentage")
        if pct is None or pct < cfg["forecast_min_percent"]:
            continue
        f = forecast(samples, index, pct, w.get("resets_at"))
        if f and (worst is None or f[0] < worst[1]):
            worst = (label, f[0])
    if worst:
        label, eta = worst
        lvl = "red" if eta < 1800 else "orange"
        add(
            "forecast",
            theme.paint(
                f"{GLYPH['rise']} {label} full {fmt_span(eta, compact=True)}", lvl
            ),
        )

    # context window of this session
    ctx = payload.get("context_window") or {}
    used = ctx.get("used_percentage")
    if used is not None:
        lvl = theme.level(used)
        add(
            "context",
            theme.paint("ctx ", "tertiary") + theme.paint(f"{used:.0f}%", lvl),
        )

    # other Claude Code sessions alive on this machine
    sessions = live_sessions()
    if sessions:
        busy = sum(1 for s in sessions if s.get("status") == "busy")
        body = theme.paint(f"{GLYPH['stack']} {len(sessions)}", "tertiary")
        if busy:
            body += " " + theme.paint(f"{GLYPH['busy']}{busy}", "green")
        add("sessions", body)

    # where you are
    ws = payload.get("workspace") or {}
    cwd = ws.get("current_dir") or payload.get("cwd") or ""
    place = ((payload.get("worktree") or {}).get("name")) or ws.get("git_worktree")
    place = place or (os.path.basename(cwd) if cwd else "")
    branch = git_branch(cwd)
    if place or branch:
        body = theme.paint(place, "secondary")
        if branch:
            body += theme.paint(f" {GLYPH['branch']} {branch}", "tertiary")
        add("location", body)

    # spend
    cost = (payload.get("cost") or {}).get("total_cost_usd") or 0
    add("cost", theme.paint(fmt_cost(cost), "tertiary"))

    return seg


def compose(payload, cfg, samples, columns=None):
    columns = columns or int(os.environ.get("COLUMNS") or 120)
    budget = max(24, columns - 2)
    sep = cfg["separator"]

    for width in (cfg["bar_width"], 6, 5, 4):
        theme = Theme(cfg["theme"], bar_style=cfg["bar_style"], bar_width=width)
        seg = build_segments(payload, cfg, theme, samples)
        order = [n for n in cfg["segments"] if n in seg]
        while order:
            plain = sep.join(seg[n]["plain"] for n in order)
            if len(plain) <= budget:
                return sep.join(seg[n]["styled"] for n in order)
            order.remove(min(order, key=lambda n: PRIORITY.get(n, 0)))
        if not seg:
            return ""
    return ""


# ---------------------------------------------------------------- panel


def panel(payload, cfg, samples):
    theme = Theme(cfg["theme"], bar_style=cfg["bar_style"], bar_width=22)
    now = time.time()
    rows = []

    def line(label, body):
        rows.append("  " + theme.paint(f"{label:<10}", "tertiary") + body)

    rows.append("  " + theme.paint("T I D E L I N E", "secondary"))
    rows.append("")

    any_limit = False
    for label, key, index in (("5-hour", "five_hour", 1), ("7-day", "seven_day", 2)):
        w = _window(payload, key)
        pct = w.get("used_percentage")
        if pct is None:
            continue
        any_limit = True
        lvl = theme.level(pct)
        body = theme.meter(pct, key=lvl) + "  " + theme.paint(f"{pct:5.1f}%", lvl)
        resets_at = w.get("resets_at")
        if resets_at:
            body += theme.paint(
                f"   resets {fmt_clock(resets_at)} · in {fmt_span(resets_at - now)}",
                "tertiary",
            )
        line(label, body)

    if not any_limit:
        line("limits", theme.paint("not reported yet — send one message", "tertiary"))

    rows.append("")
    shown = False
    for label, index, key in (("5-hour", 1, "five_hour"), ("7-day", 2, "seven_day")):
        w = _window(payload, key)
        pct = w.get("used_percentage")
        if pct is None:
            continue
        f = forecast(samples, index, pct, w.get("resets_at"))
        if not f:
            continue
        eta, rate = f
        line(
            "pace" if not shown else "",
            theme.paint(f"{rate * 60:.2f}%/min", "secondary")
            + theme.paint(
                f"   {label} exhausted in ~{fmt_span(eta)}, before it resets",
                "orange" if eta >= 1800 else "red",
            ),
        )
        shown = True
    if not shown:
        line("pace", theme.paint("steady — no window on course to run out", "tertiary"))

    rows.append("")
    ctx = payload.get("context_window") or {}
    used = ctx.get("used_percentage")
    if used is not None:
        size = ctx.get("context_window_size") or 0
        tin = ctx.get("total_input_tokens") or 0
        tout = ctx.get("total_output_tokens") or 0
        line(
            "context",
            theme.meter(used, key=theme.level(used))
            + "  "
            + theme.paint(f"{used:5.1f}%", theme.level(used))
            + theme.paint(
                f"   {fmt_tokens(tin + tout)} of {fmt_tokens(size)}   {model_label(payload)}",
                "tertiary",
            ),
        )

    sessions = live_sessions()
    busy = sum(1 for s in sessions if s.get("status") == "busy")
    line(
        "sessions",
        theme.paint(f"{len(sessions)} live", "secondary")
        + theme.paint(f" · {busy} working", "tertiary"),
    )
    for s in sessions[:8]:
        working = s.get("status") == "busy"
        dot = GLYPH["busy"] if working else GLYPH["idle"]
        rows.append(
            " " * 12
            + theme.paint(dot, "green" if working else "tertiary")
            + " "
            + theme.paint(f"{(s.get('name') or '?'):<16}", "secondary")
            + theme.paint(shorten_path(s.get("cwd") or ""), "tertiary")
        )
    if len(sessions) > 8:
        rows.append(" " * 12 + theme.paint(f"+{len(sessions) - 8} more", "tertiary"))

    cost = payload.get("cost") or {}
    line(
        "spend",
        theme.paint(fmt_cost(cost.get("total_cost_usd") or 0), "secondary")
        + theme.paint(
            f" this session · {fmt_span((cost.get('total_duration_ms') or 0) / 1000)}",
            "tertiary",
        ),
    )
    rows.append("")
    return "\n".join(rows)
