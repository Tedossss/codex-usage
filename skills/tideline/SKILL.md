---
name: tideline
description: Show, install, configure or diagnose the Tideline status line — Claude Code usage limits (5-hour and 7-day), pace forecast, and live session count. Use when the user asks how much usage they have left, when their limit resets, whether they are about to run out, how many Claude sessions are open, or wants to change how the status line looks.
---

# Tideline

Tideline reads the status-line payload Claude Code already produces and renders
usage limits, a pace forecast, and the sessions running on this machine.

The launcher is `${CLAUDE_PLUGIN_ROOT}/bin/tideline`. Run it with Bash.

## What the user is probably asking for

**"how much do I have left" / "when does my limit reset" / "am I going to run out"**

```
${CLAUDE_PLUGIN_ROOT}/bin/tideline panel
```

Print the output verbatim in a fenced block — it is pre-formatted and coloured.
Then say the one thing that matters in a sentence: the number that is highest,
when it resets, and whether the pace line says a window will run out first.

The panel reads the payload captured by the last status-line render, so it is at
most a few seconds old. If it reports no payload, the status line is not
installed — offer to install it.

**"how many sessions do I have open"**

Same panel — the sessions block lists each one with its directory and whether it
is working. A filled dot means busy, hollow means idle.

**"install it" / "set it up"**

```
${CLAUDE_PLUGIN_ROOT}/bin/tideline install
```

This rewrites `statusLine` in `~/.claude/settings.json` and saves whatever was
there before. Tell the user it appears on their next message, not immediately.
`uninstall` puts their old status line back.

**"it looks wrong" / "no colours" / "nothing shows"**

```
${CLAUDE_PLUGIN_ROOT}/bin/tideline doctor
```

Read the output before explaining. The two common answers: `rate_limits` is
absent because the account is not a Claude.ai subscription or the session has
not had a reply yet; or `truecolor` is no, which means the terminal is not
advertising `COLORTERM` and colours fall back to the 256-colour palette.

**"change how it looks" / "make it smaller" / "light terminal"**

```
${CLAUDE_PLUGIN_ROOT}/bin/tideline preview
${CLAUDE_PLUGIN_ROOT}/bin/tideline config
${CLAUDE_PLUGIN_ROOT}/bin/tideline config theme=light bar_style=hairline bar_width=6
```

`preview` renders every state, terminal width and bar style at once — show it
when the user is choosing. Options:

| key | values |
| --- | --- |
| `theme` | `dark` (default), `light` |
| `bar_style` | `solid` (default), `hairline`, `dots` |
| `bar_width` | cells in each meter, default `8` |
| `segments` | ordered list; drop any of `model five_hour seven_day forecast context sessions location cost` |
| `show_reset_above` | hide the 5-hour reset countdown below this percent, default `35` |
| `forecast_min_percent` | no pace forecast below this percent, default `12` |
| `separator` | string between segments, default three spaces |

Config lives at `~/.claude/tideline/config.json`. Values are parsed as JSON, so
quote lists: `config 'segments=["five_hour","seven_day","cost"]'`.

## Reading the line

```
Opus 5   5H ██████▋█ 84% ↺3h13m   7D ████▌███ 58%   ↗ 5H full 17m   ctx 39%   ⧉ 3 ●1   hrm ⎇ main   $2.40
```

- `5H` / `7D` — the two rate-limit windows, `↺` is time until reset
- `↗` — pace forecast; appears **only** when this session's burn rate would
  exhaust a window before that window resets. Its absence is the good news.
- `ctx` — context window of the current session
- `⧉` — Claude Code sessions alive on this machine, `●` how many are working
- Meters stay grey below 60%, then go yellow, orange, red. Grey means fine.

## Things worth knowing before you answer

- The forecast needs three samples spanning four minutes. Early in a session it
  is simply absent — do not report that as broken.
- Session counting matches processes named `claude` against the pid in each
  `~/.claude/sessions/*.json`, so it is accurate but costs one `ps`; the result
  is cached for three seconds.
- A plugin cannot own the main status line — only `settings.json` can. That is
  why `install` edits settings rather than the plugin doing it declaratively.
