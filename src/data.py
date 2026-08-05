"""Everything Tideline reads or remembers: config, live sessions, usage history."""

import json
import os
import subprocess
import time

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
STATE_DIR = os.path.join(CLAUDE_DIR, "tideline")
CONFIG_PATH = os.path.join(STATE_DIR, "config.json")
HISTORY_PATH = os.path.join(STATE_DIR, "history.json")
LAST_PAYLOAD_PATH = os.path.join(STATE_DIR, "last-payload.json")
SESSIONS_CACHE_PATH = os.path.join(STATE_DIR, "sessions-cache.json")
SESSIONS_DIR = os.path.join(CLAUDE_DIR, "sessions")

DEFAULT_CONFIG = {
    "theme": "dark",
    "bar_style": "solid",
    "bar_width": 8,
    "segments": [
        "model",
        "five_hour",
        "seven_day",
        "forecast",
        "context",
        "sessions",
        "location",
        "cost",
    ],
    "show_reset_above": 35,
    "forecast_min_percent": 12,
    "separator": "   ",
}


def ensure_state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)


def read_json(path, fallback=None):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return fallback


def write_json(path, value, indent=None):
    ensure_state_dir()
    tmp = f"{path}.tmp{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(value, fh, indent=indent)
        if indent:
            fh.write("\n")
    os.replace(tmp, path)


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    stored = read_json(CONFIG_PATH)
    if isinstance(stored, dict):
        cfg.update(stored)
    return cfg


# ---------------------------------------------------------------- sessions


def _claude_pids():
    """One ps call beats os.kill per pid: a dead session's pid gets recycled by
    an unrelated process, and only the command name tells the two apart."""
    try:
        out = subprocess.run(
            ["ps", "-Ao", "pid=,comm="], capture_output=True, text=True, timeout=2.0
        )
    except Exception:
        return None
    pids = set()
    for row in out.stdout.splitlines():
        pid, _, comm = row.strip().partition(" ")
        if "claude" in comm and pid.isdigit():
            pids.add(int(pid))
    return pids or None


def live_sessions(max_age_hours=48, ttl=3.0):
    """Cached briefly: the process scan costs ~50ms and the status line redraws
    every few seconds across every open session."""
    cached = read_json(SESSIONS_CACHE_PATH)
    if isinstance(cached, dict) and time.time() - (cached.get("at") or 0) < ttl:
        return cached.get("sessions") or []
    found = _scan_sessions(max_age_hours)
    try:
        write_json(SESSIONS_CACHE_PATH, {"at": time.time(), "sessions": found})
    except Exception:
        pass
    return found


def _scan_sessions(max_age_hours):
    cutoff_ms = (time.time() - max_age_hours * 3600) * 1000
    alive = _claude_pids()
    found = []
    try:
        names = os.listdir(SESSIONS_DIR)
    except OSError:
        return found
    for name in names:
        if not name.endswith(".json"):
            continue
        rec = read_json(os.path.join(SESSIONS_DIR, name))
        if not isinstance(rec, dict):
            continue
        if (rec.get("updatedAt") or 0) < cutoff_ms:
            continue
        pid = rec.get("pid")
        if alive is not None and pid not in alive:
            continue
        found.append(rec)
    found.sort(key=lambda r: r.get("updatedAt") or 0, reverse=True)
    return found


# ---------------------------------------------------------------- forecast

SAMPLE_INTERVAL_S = 45
HISTORY_SPAN_S = 2 * 3600
MIN_SPAN_S = 240


def record_sample(rate_limits):
    """Append a usage sample, discarding history when a limit window rolls over."""
    five = (rate_limits or {}).get("five_hour") or {}
    seven = (rate_limits or {}).get("seven_day") or {}
    if "used_percentage" not in five and "used_percentage" not in seven:
        return None

    now = time.time()
    hist = read_json(HISTORY_PATH) or {}
    samples = hist.get("samples") or []
    window_id = five.get("resets_at") or seven.get("resets_at")
    if hist.get("window_id") != window_id:
        samples = []

    entry = [
        round(now),
        five.get("used_percentage"),
        seven.get("used_percentage"),
    ]
    last = samples[-1] if samples else None
    stale = not last or (now - last[0]) >= SAMPLE_INTERVAL_S
    changed = not last or last[1] != entry[1] or last[2] != entry[2]
    if stale or changed:
        samples.append(entry)
        samples = [s for s in samples if now - s[0] <= HISTORY_SPAN_S][-120:]
        write_json(HISTORY_PATH, {"window_id": window_id, "samples": samples})
    return samples


def burn_rate(samples, index):
    """Percent consumed per second, from a least-squares fit over the samples."""
    pts = [(s[0], s[index]) for s in (samples or []) if isinstance(s[index], (int, float))]
    if len(pts) < 3 or pts[-1][0] - pts[0][0] < MIN_SPAN_S:
        return None
    n = len(pts)
    t0 = pts[0][0]
    xs = [p[0] - t0 for p in pts]
    ys = [p[1] for p in pts]
    mx = sum(xs) / n
    my = sum(ys) / n
    denom = sum((x - mx) ** 2 for x in xs)
    if denom == 0:
        return None
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / denom
    return slope if slope > 0 else None


def forecast(samples, index, current_pct, resets_at):
    """Seconds until this window is exhausted, but only when that lands before
    the window would have reset on its own — otherwise the number is noise."""
    if current_pct is None or current_pct >= 100:
        return None
    rate = burn_rate(samples, index)
    if not rate:
        return None
    eta = (100.0 - current_pct) / rate
    if resets_at:
        remaining = resets_at - time.time()
        if remaining > 0 and eta >= remaining:
            return None
    return eta, rate
