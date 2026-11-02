from __future__ import annotations

from datetime import datetime, timezone

from .models import RateWindow, UsageSnapshot


def percent(value: float) -> str:
    rounded = round(value)
    return f"{rounded}%"


def bar(value: float, width: int = 10) -> str:
    filled = round(max(0.0, min(100.0, value)) / 100 * width)
    return "█" * filled + "░" * (width - filled)


def reset_text(window: RateWindow, now: datetime | None = None) -> str:
    if window.resets_at is None:
        return "reset unavailable"
    local = window.resets_at.astimezone()
    current = now or datetime.now(timezone.utc)
    seconds = max(0, int((window.resets_at - current).total_seconds()))
    hours, remainder = divmod(seconds, 3_600)
    minutes = remainder // 60
    if hours >= 24:
        days, hours = divmod(hours, 24)
        remaining = f"{days}d {hours}h"
    elif hours:
        remaining = f"{hours}h {minutes}m"
    else:
        remaining = f"{minutes}m"
    return f"resets {local:%a %H:%M} · in {remaining}"


def age_text(captured_at: datetime, now: datetime | None = None) -> str:
    current = now or datetime.now(timezone.utc)
    seconds = max(0, int((current - captured_at).total_seconds()))
    if seconds < 60:
        return "just now"
    if seconds < 3_600:
        return f"{seconds // 60}m ago"
    if seconds < 86_400:
        return f"{seconds // 3_600}h ago"
    return f"{seconds // 86_400}d ago"


def terminal_summary(snapshot: UsageSnapshot, live_sessions: int) -> str:
    lines: list[str] = []
    for window in (snapshot.primary, snapshot.secondary):
        if window:
            lines.append(
                f"{window.label:<15} {bar(window.used_percent)} "
                f"{percent(window.used_percent):>4}  {reset_text(window)}"
            )
    if snapshot.plan_type:
        lines.append(f"Plan            {snapshot.plan_type}")
    if snapshot.tokens:
        lines.append(f"Session tokens  {snapshot.tokens.total_tokens:,}")
    lines.append(f"Live processes  {live_sessions}")
    lines.append(f"Updated         {age_text(snapshot.captured_at)}")
    return "\n".join(lines)
