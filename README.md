# Codex Usage for Arch Linux

A small KDE/Wayland tray indicator for Codex usage limits. It is an Arch Linux
port inspired by [vasfal/claude-usage](https://github.com/vasfal/claude-usage),
adapted to Codex's local session data instead of Claude credentials and APIs.

The tray label shows the shortest usage window currently reported by Codex. Its
menu shows every available primary/secondary window (commonly 5-hour and 7-day),
reset times, plan, the newest session token counters, and the number of live
Codex processes. Window names come from `window_minutes`; the app does not
assume that `primary` always means 5 hours.

## Privacy and data source

The app reads only `token_count` events from:

```text
${CODEX_HOME:-~/.codex}/sessions/**/*.jsonl
${CODEX_HOME:-~/.codex}/archived_sessions/*.jsonl
```

It never reads `auth.json`, never calls an API, and never sends telemetry. The
percentage is the latest value Codex has written locally, so it updates after
Codex receives a usage event. OpenAI also exposes current limits in Codex with
`/status` and on the Codex usage dashboard.

## Requirements

- Arch Linux
- Python 3.11+
- GTK 3, PyGObject, and Ayatana AppIndicator

```sh
sudo pacman -S --needed python python-gobject gtk3 libayatana-appindicator
```

## Install

```sh
cd /home/n_falach/codex-usage
./install.sh
```

The installer writes only to user-local XDG directories:

- `~/.local/share/codex-usage`
- `~/.local/bin/codex-usage`
- `~/.config/autostart/codex-usage.desktop`
- `~/.local/share/plasma/plasmoids/com.nfalach.codexusage`

Log out and back in, or start it immediately:

```sh
codex-usage tray
```

The same installer registers a Plasma widget named **Codex Usage**. Add it to
the panel or desktop through Plasma's widget picker. The compact view shows the
remaining percentage for the shortest reported usage window; opening it shows
reset times, a compact visual summary, and optional token/process details.

Widget settings are separate from the popup: open the widget context menu and
choose **Configure Codex Usage** to change the refresh interval or hide the
extra details row. The popup intentionally has no action-button clutter.

To update the widget after source changes, run `./install.sh` again. To remove
the widget, use `kpackagetool6 --type Plasma/Applet --remove
com.nfalach.codexusage`.

## CLI

```sh
codex-usage status
codex-usage status --json
codex-usage tray
codex-usage --codex-home /path/to/.codex status
```

`CODEX_HOME` is respected automatically.

## Development

No Python packages are downloaded. Run the tests with:

```sh
python -m unittest discover -s tests -v
python -m compileall -q codex_usage
```

## Limitations

- Values can be stale while Codex is closed because this app deliberately does
  not access account credentials or undocumented endpoints.
- Live-session counting uses `/proc` and counts Codex executables owned by the
  current user. Sandboxes or containers can hide host processes.
- The tray requires a StatusNotifier/AppIndicator host. KDE Plasma provides one
  by default; other desktops may need an extension.

## Licence and attribution

MIT. The original macOS concept and repository are copyright (c) 2026 Vasyl
Falach. This Arch/Codex implementation contains no Anthropic or OpenAI artwork
and is not affiliated with either company.
