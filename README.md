# Claude Usage

A macOS menu bar app for Claude usage limits: how much of your 5-hour and 7-day windows
you have spent, when they reset, and how many Claude Code sessions are burning them.

The repo and the SwiftPM target are called `Tideline`. The product is not.

```
menu bar    ✳ 32%

panel       ✳ Claude Usage                   MAX

            5-hour                          32 %
            ▔▔▔▔▔▔▔▔▔▔─────────────────────────
            resets 16:29               in 1h 2m

            7-day                           22 %
            ▔▔▔▔▔▔▔───────────────────────────
            resets Mon 08:59          in 4d 17h
            ──────────────────────────────────
            Sessions             18 ● 1 working
            Updated 1m ago              ⟳    ⋯
```

## The one design rule

**Grey means fine.** The bars and the number stay monochrome below 60%, then yellow,
orange, red. While calm the menu bar icon is a *template image*, so macOS tints it with the
menu bar's own appearance and it disappears into the system items — which is the point.
Colour is an interruption, and it is spent only on a warning.

The menu bar item is the Claude mark plus the percentage: the mark says whose usage this
is, the number says how much. A progress ring next to the number would say the same thing
twice, so the ring only appears when **Show percentage** is off. The mark is Anthropic's
`TrayIconTemplate` asset, copied from the installed Claude.app — their trademark, fine for
labelling your own usage on your own machine, not something to redistribute.

The pace forecast follows the same rule: it does not appear unless your current burn rate
would exhaust a window *before* that window resets. Its absence is the good news.

## Install

```sh
Scripts/build-app.sh                    # builds, signs, installs to ~/Applications
open "$HOME/Applications/Claude Usage.app"
```

Requires Swift 6 (Xcode 16+) and macOS 14+. No dependencies.

On first launch macOS asks whether Tideline may read the `Claude Code-credentials` item in
your keychain — that is the OAuth token it uses to call the usage endpoint. Click **Allow**.
It asks again after a rebuild, because the ad-hoc code signature changes with the binary.

Turn on **Open at login** from the `⋯` menu in the panel.

## Where the numbers come from

`GET https://api.anthropic.com/api/oauth/usage`, the same endpoint `/usage` uses inside
Claude Code, authorised with the token already in your keychain. That is what makes the app
standalone: it does not need a terminal open, and it does not touch your Claude Code status
line.

The response is not documented. Its shape, captured live:

```json
{ "five_hour": { "utilization": 26.0, "resets_at": "2026-08-05T13:30:00.191297+00:00" },
  "seven_day": { "utilization": 21.0, "resets_at": "2026-08-10T06:00:00.191326+00:00" },
  "seven_day_opus": null,
  "limits": [ { "kind": "session", "percent": 26, "resets_at": "…" }, … ] }
```

`Tests/` pins that shape. If Anthropic changes it, the tests fail rather than the app
silently showing nothing. The last raw exchange is always written to
`~/Library/Application Support/Tideline/last-response.json`.

Sessions come from `~/.claude/sessions/*.json`, one file per session, named by pid. The
files outlive their processes, so each pid is checked with `proc_pidpath` — note that
`proc_name` is useless here, because Claude Code's executable is named after its version
(`~/.local/share/claude/versions/2.1.222`) and so the process is called "2.1.222", never
"claude".

## Behaviour worth knowing

- **Polling** is every 120 seconds. On HTTP 429 it backs off, doubling to a 15-minute
  ceiling and honouring `Retry-After`. Launching and opening the panel both respect that
  queue; only the ⟳ button forces a request.
- **A failed request never blanks the reading.** The last good value is cached to disk, so
  a relaunch shows a number immediately, and the footer says how old it is and that it is
  retrying. The windows only move while Claude is being used, so a slightly stale number is
  still broadly true — an empty one never is.
- **The forecast** needs three samples spanning four minutes and a window already past 12%.
  Early in a window it is simply absent.
- **The icon appears on the menu bar of whichever display is active.** If your laptop's
  menu bar is full, macOS silently drops the newest item there; ⌘-drag the menu bar items
  to reorder, or turn off **Show percentage** in the `⋯` menu to make Tideline narrower.

## Layout

```
Sources/Tideline/
  Main.swift          AppKit entry point — see the comment there for why not SwiftUI's App
  AppDelegate.swift   the status item and the popover
  MenuBarIcon.swift   the mark, number and ring, drawn with Core Graphics for exact pixels
  PanelView.swift     the dropdown, SwiftUI hosted in an NSPopover
  UsageStore.swift    polling, backoff, the on-disk cache of the last good reading
  UsageAPI.swift      the request
  Usage.swift         the response, and the reader that is pinned by tests
  Keychain.swift      reading Claude Code's OAuth token
  Sessions.swift      live session discovery
  Forecast.swift      rolling history and the pace projection
  Palette.swift       the grey-until-it-matters level scale
Scripts/build-app.sh  assembles, signs and installs the bundle
```

## Development

`swift test` covers the response reader, the level scale and the keychain shape.

The bundle is assembled in a scratch directory rather than in the repo, because this
checkout lives under an iCloud-synced Desktop and codesign refuses to sign anything
carrying the xattrs that syncing attaches.

To screenshot the panel without a human clicking it:

```sh
defaults write com.vasfal.tideline autoShowPanel -bool true
open "$HOME/Applications/Claude Usage.app"   # panel opens after five seconds
defaults delete com.vasfal.tideline autoShowPanel
```
