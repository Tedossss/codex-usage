#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
install_dir="$data_home/codex-usage"
bin_dir="$HOME/.local/bin"

python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")' 2>/dev/null || {
    printf '%s\n' 'Missing GTK dependencies. Install them first:' >&2
    printf '%s\n' '  sudo pacman -S --needed python python-gobject gtk3 libayatana-appindicator' >&2
    exit 1
}

install -d "$install_dir" "$bin_dir" "$config_home/autostart"
install -m 0644 "$project_dir/run.py" "$install_dir/run.py"
install -d "$install_dir/codex_usage"
install -m 0644 "$project_dir"/codex_usage/*.py "$install_dir/codex_usage/"
install -m 0755 "$project_dir/scripts/codex-usage" "$bin_dir/codex-usage"
(
    cd "$install_dir"
    PYTHONPATH="$install_dir" python3 -c 'from codex_usage.autostart import set_enabled; set_enabled(True)'
)

if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -q 'com.nfalach.codexusage'; then
        kpackagetool6 --type Plasma/Applet --upgrade "$project_dir/plasmoid" >/dev/null
    else
        kpackagetool6 --type Plasma/Applet --install "$project_dir/plasmoid" >/dev/null
    fi
else
    printf '%s\n' 'kpackagetool6 not found; the CLI/tray was installed, but the Plasma widget was skipped.' >&2
fi

printf 'Installed Codex Usage. Start it with: %s\n' "$bin_dir/codex-usage tray"
