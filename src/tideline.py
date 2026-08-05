#!/usr/bin/env python3
"""Tideline — a Claude Code status line for usage limits.

  render      read a status-line payload on stdin, print one line   (Claude Code calls this)
  panel       print the expanded view from the last captured payload
  install     point ~/.claude/settings.json at this status line
  uninstall   restore whatever status line was there before
  doctor      report what Tideline can and cannot see
  preview     render every state, width and bar style at once
  config      show or set options
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import data  # noqa: E402
import render  # noqa: E402
from theme import Theme  # noqa: E402

SETTINGS_PATH = os.path.join(data.CLAUDE_DIR, "settings.json")
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCHER = os.path.join(HERE, "bin", "tideline")


def _read_payload_from_stdin():
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    try:
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def cmd_render(_args):
    payload = _read_payload_from_stdin()
    cfg = data.load_config()
    samples = data.record_sample(payload.get("rate_limits"))
    if samples is None:
        samples = (data.read_json(data.HISTORY_PATH) or {}).get("samples") or []
    if payload:
        try:
            data.write_json(data.LAST_PAYLOAD_PATH, payload)
        except Exception:
            pass
    sys.stdout.write(render.compose(payload, cfg, samples))
    return 0


def cmd_panel(_args):
    payload = data.read_json(data.LAST_PAYLOAD_PATH) or {}
    cfg = data.load_config()
    samples = (data.read_json(data.HISTORY_PATH) or {}).get("samples") or []
    if not payload:
        print("  Tideline has no payload yet. Install the status line and send a message.")
        return 1
    print(render.panel(payload, cfg, samples))
    return 0


def cmd_install(_args):
    data.ensure_state_dir()
    settings = data.read_json(SETTINGS_PATH)
    if settings is None:
        print(f"Cannot read {SETTINGS_PATH}", file=sys.stderr)
        return 1

    previous = settings.get("statusLine")
    if previous and previous.get("command", "").find("tideline") == -1:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        backup = os.path.join(data.STATE_DIR, f"settings.backup-{stamp}.json")
        data.write_json(backup, settings)
        data.write_json(
            os.path.join(data.STATE_DIR, "previous-statusline.json"), previous
        )
        print(f"  Previous status line saved to {backup}")

    settings["statusLine"] = {
        "type": "command",
        "command": f"{LAUNCHER} render",
        "refreshInterval": 5,
        "padding": 0,
    }
    data.write_json(SETTINGS_PATH, settings)
    print(f"  Tideline installed → {LAUNCHER} render")
    print("  It appears on your next interaction with Claude Code.")
    return 0


def cmd_uninstall(_args):
    settings = data.read_json(SETTINGS_PATH)
    if settings is None:
        return 1
    previous = data.read_json(os.path.join(data.STATE_DIR, "previous-statusline.json"))
    if previous:
        settings["statusLine"] = previous
        print("  Restored your previous status line.")
    else:
        settings.pop("statusLine", None)
        print("  Removed the status line.")
    data.write_json(SETTINGS_PATH, settings)
    return 0


def cmd_doctor(_args):
    cfg = data.load_config()
    theme = Theme(cfg["theme"], bar_style=cfg["bar_style"], bar_width=cfg["bar_width"])
    payload = data.read_json(data.LAST_PAYLOAD_PATH) or {}
    hist = data.read_json(data.HISTORY_PATH) or {}
    limits = payload.get("rate_limits") or {}
    sessions = data.live_sessions()

    def row(k, v):
        print(f"  {k:<22}{v}")

    print()
    print("  " + theme.paint("T I D E L I N E   ·   doctor", "secondary"))
    print()
    row("python", sys.version.split()[0])
    row("truecolor", "yes" if theme.truecolor else f"no (COLORTERM={os.environ.get('COLORTERM', 'unset')})")
    row("columns", os.environ.get("COLUMNS", "unset"))
    row("launcher", LAUNCHER)
    row("settings", SETTINGS_PATH)
    installed = (data.read_json(SETTINGS_PATH) or {}).get("statusLine", {}).get("command", "")
    row("wired up", "yes" if "tideline" in installed else f"no ({installed or 'none'})")
    row("last payload", time.strftime("%H:%M:%S", time.localtime(os.path.getmtime(data.LAST_PAYLOAD_PATH))) if os.path.exists(data.LAST_PAYLOAD_PATH) else "never")
    row("rate_limits", ", ".join(limits.keys()) if limits else "absent (Pro/Max only, after first reply)")
    row("history samples", len(hist.get("samples") or []))
    row("live sessions", len(sessions))
    print()
    print("  preview")
    print("  " + render.compose(payload, cfg, hist.get("samples") or []))
    print()
    for style in ("solid", "hairline", "dots"):
        t = Theme(cfg["theme"], bar_style=style, bar_width=14)
        print(f"  {style:<10}" + "  ".join(t.meter(p) for p in (18, 55, 84, 97)))
    print()
    return 0


SCENARIOS = [
    ("fresh", 2.0, 0.4, None),
    ("working", 23.5, 12.0, None),
    ("warm", 62.4, 24.1, None),
    ("hot", 84.0, 57.5, 0.9),
    ("critical", 96.2, 91.0, 2.4),
    ("no limits yet", None, None, None),
]


def _scenario_payload(five, seven):
    now = time.time()
    payload = {
        "cwd": os.getcwd(),
        "model": {"id": "claude-opus-5[1m]", "display_name": "Opus 5 (1M context)"},
        "workspace": {"current_dir": os.getcwd()},
        "cost": {"total_cost_usd": 2.40, "total_duration_ms": 2_530_000},
        "context_window": {
            "total_input_tokens": 382_000,
            "total_output_tokens": 4_200,
            "context_window_size": 1_000_000,
            "used_percentage": 38.6,
        },
        "effort": {"level": "high"},
    }
    if five is not None:
        payload["rate_limits"] = {
            "five_hour": {"used_percentage": five, "resets_at": now + 11_640},
            "seven_day": {"used_percentage": seven, "resets_at": now + 371_000},
        }
    return payload


def _synthetic_samples(five, seven, per_min):
    """Twenty minutes of history rising at `per_min` percent a minute."""
    now = time.time()
    return [
        [round(now - s), five - (s / 60.0) * per_min, seven - (s / 60.0) * per_min / 3]
        for s in range(1200, -1, -60)
    ]


def cmd_preview(_args):
    cfg = data.load_config()
    theme = Theme(cfg["theme"])
    print()
    print("  " + theme.paint("T I D E L I N E   ·   states", "secondary"))
    print()
    for name, five, seven, per_min in SCENARIOS:
        payload = _scenario_payload(five, seven)
        samples = _synthetic_samples(five, seven, per_min) if per_min else []
        print("  " + theme.paint(f"{name:<15}", "tertiary") + render.compose(payload, cfg, samples))
    print()
    print("  " + theme.paint("T I D E L I N E   ·   widths", "secondary"))
    print()
    payload = _scenario_payload(84.0, 57.5)
    samples = _synthetic_samples(84.0, 57.5, 0.9)
    for cols in (160, 120, 100, 80, 60, 44):
        print(
            "  "
            + theme.paint(f"{cols:<15}", "tertiary")
            + render.compose(payload, cfg, samples, columns=cols)
        )
    print()
    print("  " + theme.paint("T I D E L I N E   ·   bar styles", "secondary"))
    print()
    for style in ("solid", "hairline", "dots"):
        t = Theme(cfg["theme"], bar_style=style, bar_width=16)
        print(
            "  "
            + t.paint(f"{style:<15}", "tertiary")
            + "   ".join(t.meter(p) for p in (8, 34, 62, 85, 97))
        )
    print()
    return 0


def cmd_config(args):
    cfg = data.load_config()
    if not args:
        print(json.dumps(cfg, indent=2))
        return 0
    stored = data.read_json(data.CONFIG_PATH) or {}
    for pair in args:
        if "=" not in pair:
            print(f"  expected key=value, got {pair}", file=sys.stderr)
            return 1
        key, value = pair.split("=", 1)
        if key not in data.DEFAULT_CONFIG:
            print(f"  unknown key {key}", file=sys.stderr)
            return 1
        try:
            stored[key] = json.loads(value)
        except Exception:
            stored[key] = value
    data.write_json(data.CONFIG_PATH, stored)
    print(json.dumps(data.load_config(), indent=2))
    return 0


COMMANDS = {
    "render": cmd_render,
    "panel": cmd_panel,
    "install": cmd_install,
    "uninstall": cmd_uninstall,
    "doctor": cmd_doctor,
    "preview": cmd_preview,
    "config": cmd_config,
}


def main(argv):
    name = argv[0] if argv else "render"
    fn = COMMANDS.get(name)
    if not fn:
        print(__doc__)
        return 1
    return fn(argv[1:])


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
