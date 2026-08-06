from __future__ import annotations

import webbrowser
from datetime import datetime
from pathlib import Path

from . import autostart
from .formatting import age_text, bar, percent, reset_text
from .models import UsageSnapshot
from .reader import count_live_codex_processes, latest_snapshot


USAGE_DASHBOARD = "https://chatgpt.com/codex/settings/usage"


class TrayApplication:
    def __init__(self, codex_home: Path, interval_seconds: int = 15) -> None:
        import gi

        gi.require_version("Gtk", "3.0")
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import AyatanaAppIndicator3, GLib, Gtk

        self.GLib = GLib
        self.Gtk = Gtk
        self.codex_home = codex_home
        self.snapshot: UsageSnapshot | None = None

        initialized, _arguments = Gtk.init_check()
        if not initialized:
            raise RuntimeError(
                "GTK could not connect to a graphical session. "
                "Run tray mode from your Plasma desktop, not a headless shell."
            )

        self.indicator = AyatanaAppIndicator3.Indicator.new(
            "codex-usage",
            "utilities-system-monitor-symbolic",
            AyatanaAppIndicator3.IndicatorCategory.SYSTEM_SERVICES,
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Codex Usage")

        self.menu = Gtk.Menu()
        self.primary_item = self._label_item("Waiting for Codex usage…")
        self.secondary_item = self._label_item("")
        self.details_item = self._label_item("")
        self.updated_item = self._label_item("")
        for item in (self.primary_item, self.secondary_item, self.details_item, self.updated_item):
            self.menu.append(item)
        self.menu.append(Gtk.SeparatorMenuItem())

        refresh = Gtk.MenuItem(label="Refresh")
        refresh.connect("activate", lambda _item: self.refresh())
        self.menu.append(refresh)

        dashboard = Gtk.MenuItem(label="Open Codex usage dashboard")
        dashboard.connect("activate", lambda _item: webbrowser.open(USAGE_DASHBOARD))
        self.menu.append(dashboard)

        self.autostart_item = Gtk.CheckMenuItem(label="Start at login")
        self.autostart_item.set_active(autostart.enabled())
        self.autostart_item.connect("toggled", self._toggle_autostart)
        self.menu.append(self.autostart_item)
        self.menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda _item: Gtk.main_quit())
        self.menu.append(quit_item)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)
        self.refresh()
        GLib.timeout_add_seconds(interval_seconds, self.refresh)

    def _label_item(self, text: str):
        item = self.Gtk.MenuItem(label=text)
        item.set_sensitive(False)
        return item

    def _toggle_autostart(self, item) -> None:
        autostart.set_enabled(item.get_active())

    def refresh(self) -> bool:
        self.snapshot = latest_snapshot(self.codex_home)
        live = count_live_codex_processes()
        if self.snapshot is None:
            self.indicator.set_label("—", "100%")
            self.primary_item.set_label("No local Codex usage found")
            self.secondary_item.set_label(f"Checked {self.codex_home}")
            self.details_item.set_label(f"Live Codex processes: {live}")
            self.updated_item.set_label("Run Codex once, then refresh")
            return True

        available = [window for window in (self.snapshot.primary, self.snapshot.secondary) if window]
        tracked = min(
            available,
            key=lambda window: window.window_minutes or 10**9,
            default=None,
        )
        label = percent(tracked.used_percent) if tracked else "—"
        self.indicator.set_label(label, "100%")
        self._set_window(self.primary_item, self.snapshot.primary, "Primary")
        self._set_window(self.secondary_item, self.snapshot.secondary, "Secondary")

        plan = self.snapshot.plan_type or "unknown plan"
        token_text = ""
        if self.snapshot.tokens:
            token_text = f" · {self.snapshot.tokens.total_tokens:,} session tokens"
        self.details_item.set_label(f"{plan} · {live} live Codex processes{token_text}")
        self.updated_item.set_label(f"Updated {age_text(self.snapshot.captured_at)}")
        return True

    def _set_window(self, item, window, fallback: str) -> None:
        if window is None:
            item.set_label(f"{fallback}: unavailable")
            return
        item.set_label(
            f"{window.label}: {bar(window.used_percent)} {percent(window.used_percent)} · "
            f"{reset_text(window)}"
        )

    def run(self) -> None:
        self.Gtk.main()


def run_tray(codex_home: Path) -> int:
    try:
        app = TrayApplication(codex_home)
    except RuntimeError:
        raise
    except (ImportError, ValueError) as error:
        raise RuntimeError(
            "GTK/AppIndicator is unavailable. On Arch install: "
            "sudo pacman -S python-gobject gtk3 libayatana-appindicator"
        ) from error
    app.run()
    return 0
