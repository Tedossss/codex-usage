from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__
from .formatting import terminal_summary
from .reader import count_live_codex_processes, default_codex_home, latest_snapshot


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Show local Codex usage limits on Arch Linux")
    root.add_argument("--version", action="version", version=__version__)
    root.add_argument("--codex-home", type=Path, default=default_codex_home())
    commands = root.add_subparsers(dest="command")
    status = commands.add_parser("status", help="print the latest local usage reading")
    status.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    commands.add_parser("tray", help="run the system tray indicator")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    command = args.command or "status"
    if command == "tray":
        from .tray import run_tray

        try:
            return run_tray(args.codex_home)
        except RuntimeError as error:
            print(f"codex-usage: {error}", file=sys.stderr)
            return 2

    snapshot = latest_snapshot(args.codex_home)
    if snapshot is None:
        print(f"codex-usage: no token_count events found under {args.codex_home}", file=sys.stderr)
        return 1
    live = count_live_codex_processes()
    if args.json:
        output = snapshot.to_dict()
        output["live_processes"] = live
        print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    else:
        print(terminal_summary(snapshot, live))
    return 0
