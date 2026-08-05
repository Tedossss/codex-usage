# Tideline

A status line for Claude Code that answers the question you actually have:
**how much is left, and am I about to run out.**

```
Opus 5   5H ██████▋█ 84% ↺3h13m   7D ████▌███ 58%   ↗ 5H full 17m   ctx 39%   ⧉ 3 ●1   hrm ⎇ main   $2.40
```

## What it shows

| | |
| --- | --- |
| `5H` `7D` | the two Claude.ai rate-limit windows, as continuous meters with 1/8-cell resolution |
| `↺` | time until that window resets |
| `↗` | **pace forecast** — when your current burn rate would exhaust a window *before* it resets |
| `ctx` | context window of this session |
| `⧉` | Claude Code sessions alive on this machine, and how many are working right now |
| | current directory or worktree, branch, session spend |

## The one design rule

**Grey means fine.** The meters are monochrome until 60%, then yellow, then
orange, then red. The pace forecast is not shown at all unless you are on course
to hit a wall. A status line you have learned to ignore is a broken status line,
so Tideline stays quiet until it has something to say.

Everything else follows from that: no icons that decorate rather than inform, no
colour that does not encode a state, no segment that cannot be removed. When the
terminal narrows, segments drop in reverse order of usefulness — spend first,
the 5-hour meter last.

## Install

```sh
git clone <this repo> ~/Desktop/projects/tideline
~/Desktop/projects/tideline/bin/tideline install
```

`install` rewrites `statusLine` in `~/.claude/settings.json` and saves whatever
was there before to `~/.claude/tideline/`. `uninstall` puts it back.

Requires Python 3.8+ (macOS and most Linux ship it). No packages to install.

Also install as a plugin for the `/tideline` skill, which turns "how much have I
got left?" in chat into the expanded panel:

```sh
claude plugin marketplace add ~/Desktop/projects/tideline
claude plugin install tideline@tideline
```

## Commands

| | |
| --- | --- |
| `tideline panel` | the expanded view — both windows, pace, every live session |
| `tideline preview` | every state, terminal width and bar style at once |
| `tideline doctor` | what Tideline can and cannot see, and why |
| `tideline config` | show options |
| `tideline config theme=light bar_style=hairline` | set them |
| `tideline install` / `uninstall` | wire it into settings, or unwire it |

## How the forecast works

Every render samples `rate_limits` into `~/.claude/tideline/history.json`, at
most once every 45 seconds, discarded when a window rolls over. A least-squares
fit over the last two hours gives percent-per-second; that projects a time of
exhaustion. It is shown only when three conditions hold: at least three samples
spanning four minutes, the window is already past 12%, and the projected
exhaustion lands *before* the window would have reset anyway. Otherwise the
number would be technically true and practically noise.

## Notes

- `rate_limits` is only sent to status lines for Claude.ai Pro and Max accounts,
  and only after the session's first reply. Before then those segments are
  absent rather than zero.
- Session counting matches live processes named `claude` against the pid in each
  `~/.claude/sessions/*.json`; a pid alone is not enough, because pids get
  recycled and the session files outlive their processes. The scan costs one
  `ps` and is cached for three seconds.
- A Claude Code plugin cannot declare the main status line — only `settings.json`
  can — which is why `install` edits settings instead.
- A render costs about 50 ms, on a five-second refresh.

## Layout

```
bin/tideline          launcher; resolves its own path, finds python3
src/tideline.py       CLI: render, panel, install, uninstall, doctor, preview, config
src/render.py         composes the line and the panel; width budget and degradation
src/theme.py          Apple system palette, truecolor with a 256-colour fallback, meters
src/data.py           config, live session discovery, usage history and forecast
skills/tideline/      the /tideline skill
```
