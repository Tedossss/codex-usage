from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from .models import RateWindow, TokenUsage, UsageSnapshot


def default_codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME")
    return Path(configured).expanduser() if configured else Path.home() / ".codex"


def session_files(codex_home: Path) -> list[Path]:
    files = list((codex_home / "sessions").glob("**/*.jsonl"))
    files.extend((codex_home / "archived_sessions").glob("*.jsonl"))
    return sorted(set(files), key=_mtime, reverse=True)


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0


def reverse_lines(path: Path, block_size: int = 65_536) -> Iterator[str]:
    """Yield UTF-8 lines from the end without loading a whole transcript."""
    with path.open("rb") as stream:
        stream.seek(0, os.SEEK_END)
        position = stream.tell()
        remainder = b""
        while position:
            size = min(block_size, position)
            position -= size
            stream.seek(position)
            chunk = stream.read(size) + remainder
            lines = chunk.split(b"\n")
            remainder = lines[0]
            for line in reversed(lines[1:]):
                if line:
                    yield line.decode("utf-8", errors="replace")
        if remainder:
            yield remainder.decode("utf-8", errors="replace")


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _integer(value: Any) -> int | None:
    number = _number(value)
    return int(number) if number is not None else None


def _timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _window(value: Any) -> RateWindow | None:
    if not isinstance(value, dict):
        return None
    percent = _number(value.get("used_percent"))
    if percent is None:
        return None
    reset = value.get("resets_at")
    resets_at = datetime.fromtimestamp(reset, timezone.utc) if _number(reset) is not None else None
    return RateWindow(
        used_percent=max(0.0, min(100.0, percent)),
        window_minutes=_integer(value.get("window_minutes")),
        resets_at=resets_at,
    )


def parse_token_count_event(raw: str, source: Path | str = "") -> UsageSnapshot | None:
    try:
        event = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None
    if event.get("type") != "event_msg":
        return None
    payload = event.get("payload")
    if not isinstance(payload, dict) or payload.get("type") != "token_count":
        return None

    captured_at = _timestamp(event.get("timestamp"))
    limits = payload.get("rate_limits")
    if captured_at is None or not isinstance(limits, dict):
        return None

    info = payload.get("info")
    total = info.get("total_token_usage") if isinstance(info, dict) else None
    tokens = None
    if isinstance(total, dict):
        tokens = TokenUsage(
            input_tokens=_integer(total.get("input_tokens")) or 0,
            cached_input_tokens=_integer(total.get("cached_input_tokens")) or 0,
            output_tokens=_integer(total.get("output_tokens")) or 0,
            reasoning_output_tokens=_integer(total.get("reasoning_output_tokens")) or 0,
            total_tokens=_integer(total.get("total_tokens")) or 0,
        )

    plan = limits.get("plan_type")
    return UsageSnapshot(
        captured_at=captured_at,
        source=str(source),
        primary=_window(limits.get("primary")),
        secondary=_window(limits.get("secondary")),
        plan_type=plan if isinstance(plan, str) else None,
        tokens=tokens,
    )


def latest_snapshot(codex_home: Path | None = None) -> UsageSnapshot | None:
    newest: UsageSnapshot | None = None
    for path in session_files(codex_home or default_codex_home()):
        try:
            for line in reverse_lines(path):
                candidate = parse_token_count_event(line, path)
                if candidate:
                    if newest is None or candidate.captured_at > newest.captured_at:
                        newest = candidate
                    break
        except OSError:
            continue
    return newest


def classify_codex_process(executable: str, arguments: list[str]) -> str | None:
    """Classify a process without counting Codex helper children as sessions."""
    path = executable.lower()
    name = Path(path).name
    args = [argument.lower() for argument in arguments]
    joined = "\0".join(args)

    if name == "codex" or (name.startswith("codex-") and "sandbox" not in name):
        if "code-mode-host" not in name:
            return "native"
    if "codex-linux-sandbox" in args or "--argv0\0codex-linux-sandbox" in joined:
        return "launcher"
    if args and Path(args[0]).name in {"node", "node-mainthread"}:
        if any(argument.endswith("/codex") or argument.endswith("/codex.js") for argument in args[1:]):
            return "launcher"
    return None


def count_live_codex_processes() -> int:
    """Count current-user Codex sessions visible through Linux /proc.

    A normal npm installation has both a Node launcher and one native `codex`
    child. Prefer native processes so each session is counted once. Inside the
    Codex sandbox only the outer `codex-linux-sandbox` bwrap may be visible, so
    launchers are used as a fallback.
    """
    proc = Path("/proc")
    try:
        uid = os.getuid()
        entries = list(proc.iterdir())
    except OSError:
        return 0

    native = 0
    launchers = 0
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            executable = (entry / "exe").resolve(strict=True)
            raw_arguments = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        arguments = [
            value.decode("utf-8", errors="replace")
            for value in raw_arguments.split(b"\0")
            if value
        ]
        classification = classify_codex_process(str(executable), arguments)
        if classification == "native":
            native += 1
        elif classification == "launcher":
            launchers += 1
    return native or launchers
