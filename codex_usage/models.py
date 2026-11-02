from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any


@dataclass(frozen=True)
class RateWindow:
    used_percent: float
    window_minutes: int | None
    resets_at: datetime | None

    @property
    def label(self) -> str:
        if self.window_minutes == 300:
            return "5-hour window"
        if self.window_minutes == 10_080:
            return "7-day window"
        if self.window_minutes and self.window_minutes % 1_440 == 0:
            return f"{self.window_minutes // 1_440}-day window"
        if self.window_minutes and self.window_minutes % 60 == 0:
            return f"{self.window_minutes // 60}-hour window"
        return "Usage window"


@dataclass(frozen=True)
class TokenUsage:
    input_tokens: int = 0
    cached_input_tokens: int = 0
    output_tokens: int = 0
    reasoning_output_tokens: int = 0
    total_tokens: int = 0


@dataclass(frozen=True)
class UsageSnapshot:
    captured_at: datetime
    source: str
    primary: RateWindow | None
    secondary: RateWindow | None
    plan_type: str | None
    tokens: TokenUsage | None

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["captured_at"] = self.captured_at.isoformat()
        for name in ("primary", "secondary"):
            window = value[name]
            if window and window["resets_at"]:
                window["resets_at"] = window["resets_at"].isoformat()
        return value
