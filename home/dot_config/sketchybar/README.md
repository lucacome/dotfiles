# sketchybar config

macOS status bar built with [SketchyBar](https://github.com/FelixKratz/SketchyBar)
and SbarLua.

Left: Apple menu, then either the front app's menus or AeroSpace workspaces
(click the apple/indicator to swap).
Right: front app, clock, media, battery, volume, wifi, CPU/RAM, weather.

## Requirements

| Tool | Used for |
| --- | --- |
| `sketchybar` | the bar (`brew install sketchybar`) |
| SbarLua | `~/.local/share/sketchybar_lua/sketchybar.so` |
| `aerospace` | workspace list and clicking |
| `jq`, `curl` | weather (`wttr.in`) |
| `nowplaying-cli` | media buttons (`brew install nowplaying-cli`) |
| `SwitchAudioSource` | volume popup device list (`brew install switchaudio-osx`) |
| SF Pro, SF Mono, sketchybar-app-font | all text and app icons (installed manually) |

The menu bar browser (`helpers/menus`) needs SketchyBar (or the terminal that
starts it) allowed under System Settings → Privacy & Security → Accessibility.

## Files

- `sketchybarrc` → `helpers/init.lua` (builds helpers) → `init.lua`
- `bar.lua`, `default.lua`, `colors.lua`, `icons.lua`, `settings.lua` — look and feel
- `items/` — one file per bar item, `items/widgets/` for the right side
- `helpers/event_providers/` — CPU and network event producers (C)
- `helpers/menus/` — clicks the focused app's menu bar (C, private APIs)
- `helpers/frontmost_watch/` — prints the front window id (used to close popups)
- `helpers/wake_watch/` — detached watchdog: probes the bar after a wake and
  force-kills it if it stays silent for ~20s (SketchyBar's SkyLight connection
  can wedge on wake; only a fresh process recovers)

## Building

Helpers are rebuilt automatically on every config load: `helpers/init.lua` runs
`make -s` in `helpers/`, which is incremental (about 70 ms when nothing
changed). After editing a `.c`/`.m`/`.h`, just reload the bar.

Manual build: `make -C helpers`
The automatic build on config load writes its output to `helpers/build.log`; a
failure is reported on stderr instead of being swallowed.

Tests: `lua tests.lua` (run from this directory) checks the pure Lua helpers.

## After a wake

SketchyBar destroys and recreates all bar windows on wake (twice: once on the
wake notification, once 0.5s later), so the bar vanishes for the length of that
rebuild. That is upstream behaviour and cannot be disabled from the config.
`helpers/wake_watch` runs detached and waits for the rebuild; if the bar still
does not answer after ~20s, it kills it and launchd relaunches it. Log lives in
`~/.local/state/sketchybar/`.

