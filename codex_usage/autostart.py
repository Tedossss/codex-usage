from __future__ import annotations

import os
import sys
from pathlib import Path


def _exec_arg(value: str) -> str:
    return f'"{value.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34))}"'


def desktop_entry() -> str:
    run_script = Path(__file__).resolve().parent.parent / "run.py"
    command = f"{_exec_arg(sys.executable)} {_exec_arg(str(run_script))} tray"
    return f"""[Desktop Entry]
Type=Application
Name=Codex Usage
Comment=Show Codex usage limits in the system tray
Exec={command}
Icon=utilities-system-monitor
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
"""


def autostart_path() -> Path:
    root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return root / "autostart" / "codex-usage.desktop"


def enabled() -> bool:
    return autostart_path().is_file()


def set_enabled(value: bool) -> None:
    path = autostart_path()
    if value:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(desktop_entry(), encoding="utf-8")
    else:
        path.unlink(missing_ok=True)
